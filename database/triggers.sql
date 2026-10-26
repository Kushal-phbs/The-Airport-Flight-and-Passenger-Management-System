-- =====================================================================
-- Airport Flight and Passenger Management System
-- triggers.sql  -- run AFTER schema.sql and seed_data.sql
-- Re-runnable: every object is dropped before it is created.
--
-- Flask should run  SET @app_user_id = <logged-in user id>;  on its DB
-- connection before each request so triggers can record WHO did what.
-- =====================================================================
USE airport_db;

DELIMITER $$

-- =====================================================================
-- HELPER PROCEDURES (called from triggers)
-- =====================================================================

DROP PROCEDURE IF EXISTS sp_audit$$
CREATE PROCEDURE sp_audit(
    IN p_action VARCHAR(50), IN p_table VARCHAR(50), IN p_record_id INT,
    IN p_old TEXT, IN p_new TEXT)
BEGIN
    INSERT INTO AUDIT_LOG (user_id, action, table_name, record_id, old_value, new_value)
    VALUES ((SELECT user_id FROM USER_ACCOUNT WHERE user_id = @app_user_id),
            p_action, p_table, p_record_id, p_old, p_new);
END$$

DROP PROCEDURE IF EXISTS sp_validate_flight$$
CREATE PROCEDURE sp_validate_flight(
    IN p_flight_id INT, IN p_airline INT, IN p_aircraft INT,
    IN p_src INT, IN p_dst INT, IN p_gate INT,
    IN p_dep_date DATE, IN p_dep_time TIME,
    IN p_arr_date DATE, IN p_arr_time TIME)
BEGIN
    DECLARE v_ac_airline INT;
    DECLARE v_ac_status  VARCHAR(20);
    DECLARE v_gate_airport INT;
    DECLARE v_gate_status  VARCHAR(20);
    DECLARE v_cnt INT DEFAULT 0;
    DECLARE v_dep DATETIME;
    DECLARE v_arr DATETIME;

    SET v_dep = TIMESTAMP(p_dep_date, p_dep_time);
    SET v_arr = TIMESTAMP(p_arr_date, p_arr_time);

    -- 1. source <> destination
    IF p_src = p_dst THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Source and destination airports must be different';
    END IF;

    -- 2. aircraft must belong to the airline and be active
    SELECT airline_id, status INTO v_ac_airline, v_ac_status
    FROM AIRCRAFT WHERE aircraft_id = p_aircraft;
    IF v_ac_airline <> p_airline THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Aircraft does not belong to the selected airline';
    END IF;
    IF v_ac_status <> 'Active' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Aircraft is not active (maintenance or retired)';
    END IF;

    -- 3. aircraft cannot be on two overlapping flights
    SELECT COUNT(*) INTO v_cnt
    FROM FLIGHT f
    WHERE f.aircraft_id = p_aircraft
      AND f.flight_id <> p_flight_id
      AND f.status <> 'Cancelled'
      AND TIMESTAMP(f.departure_date, f.departure_time) < v_arr
      AND TIMESTAMP(f.arrival_date,   f.arrival_time)   > v_dep;
    IF v_cnt > 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Aircraft is already assigned to an overlapping flight';
    END IF;

    -- 4. gate rules
    IF p_gate IS NOT NULL THEN
        SELECT airport_id, status INTO v_gate_airport, v_gate_status
        FROM GATE WHERE gate_id = p_gate;

        IF v_gate_airport <> p_src THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Gate must belong to the departure airport';
        END IF;
        IF v_gate_status = 'Closed' THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Gate is closed';
        END IF;

        SELECT COUNT(*) INTO v_cnt
        FROM FLIGHT f
        WHERE f.gate_id = p_gate
          AND f.flight_id <> p_flight_id
          AND f.status <> 'Cancelled'
          AND ABS(TIMESTAMPDIFF(MINUTE,
                  TIMESTAMP(f.departure_date, f.departure_time), v_dep)) < 60;
        IF v_cnt > 0 THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Gate is already allocated to another flight within 60 minutes';
        END IF;
    END IF;
END$$

-- =====================================================================
-- FLIGHT
-- =====================================================================

DROP TRIGGER IF EXISTS trg_flight_bi$$
CREATE TRIGGER trg_flight_bi BEFORE INSERT ON FLIGHT FOR EACH ROW
BEGIN
    CALL sp_validate_flight(0, NEW.airline_id, NEW.aircraft_id,
                            NEW.source_airport_id, NEW.destination_airport_id, NEW.gate_id,
                            NEW.departure_date, NEW.departure_time,
                            NEW.arrival_date, NEW.arrival_time);
END$$

DROP TRIGGER IF EXISTS trg_flight_bu$$
CREATE TRIGGER trg_flight_bu BEFORE UPDATE ON FLIGHT FOR EACH ROW
BEGIN
    -- re-validate only when something relevant changed
    IF NOT (OLD.gate_id <=> NEW.gate_id)
       OR OLD.departure_date <> NEW.departure_date OR OLD.departure_time <> NEW.departure_time
       OR OLD.arrival_date   <> NEW.arrival_date   OR OLD.arrival_time   <> NEW.arrival_time
       OR OLD.source_airport_id <> NEW.source_airport_id
       OR OLD.destination_airport_id <> NEW.destination_airport_id
       OR OLD.aircraft_id <> NEW.aircraft_id OR OLD.airline_id <> NEW.airline_id THEN
        CALL sp_validate_flight(NEW.flight_id, NEW.airline_id, NEW.aircraft_id,
                                NEW.source_airport_id, NEW.destination_airport_id, NEW.gate_id,
                                NEW.departure_date, NEW.departure_time,
                                NEW.arrival_date, NEW.arrival_time);
    END IF;

    IF OLD.status = 'Cancelled' AND NEW.status <> 'Cancelled' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'A cancelled flight cannot be reactivated';
    END IF;

    -- actual departure -> compute delay, mark Departed
    IF NEW.actual_departure IS NOT NULL AND NOT (OLD.actual_departure <=> NEW.actual_departure) THEN
        SET NEW.delay_minutes = GREATEST(0, TIMESTAMPDIFF(MINUTE,
                TIMESTAMP(NEW.departure_date, NEW.departure_time), NEW.actual_departure));
        IF NEW.status IN ('Scheduled', 'Boarding', 'Delayed') THEN
            SET NEW.status = 'Departed';
        END IF;
    END IF;

    -- actual arrival -> mark Arrived
    IF NEW.actual_arrival IS NOT NULL AND NOT (OLD.actual_arrival <=> NEW.actual_arrival) THEN
        IF NEW.actual_departure IS NOT NULL AND NEW.actual_arrival < NEW.actual_departure THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Actual arrival cannot be before actual departure';
        END IF;
        SET NEW.status = 'Arrived';
    END IF;
END$$

DROP TRIGGER IF EXISTS trg_flight_ai$$
CREATE TRIGGER trg_flight_ai AFTER INSERT ON FLIGHT FOR EACH ROW
BEGIN
    CALL sp_audit('INSERT', 'FLIGHT', NEW.flight_id, NULL,
        JSON_OBJECT('flight_no', NEW.flight_no, 'status', NEW.status,
                    'gate_id', NEW.gate_id, 'aircraft_id', NEW.aircraft_id));
END$$

DROP TRIGGER IF EXISTS trg_flight_au$$
CREATE TRIGGER trg_flight_au AFTER UPDATE ON FLIGHT FOR EACH ROW
BEGIN
    -- cancelling a flight cancels all its bookings (booking trigger handles refunds)
    IF OLD.status <> 'Cancelled' AND NEW.status = 'Cancelled' THEN
        UPDATE BOOKING SET booking_status = 'Cancelled'
        WHERE flight_id = NEW.flight_id AND booking_status <> 'Cancelled';
    END IF;

    CALL sp_audit('UPDATE', 'FLIGHT', NEW.flight_id,
        JSON_OBJECT('status', OLD.status, 'gate_id', OLD.gate_id, 'delay_minutes', OLD.delay_minutes),
        JSON_OBJECT('status', NEW.status, 'gate_id', NEW.gate_id, 'delay_minutes', NEW.delay_minutes));
END$$

DROP TRIGGER IF EXISTS trg_flight_ad$$
CREATE TRIGGER trg_flight_ad AFTER DELETE ON FLIGHT FOR EACH ROW
BEGIN
    CALL sp_audit('DELETE', 'FLIGHT', OLD.flight_id,
        JSON_OBJECT('flight_no', OLD.flight_no, 'status', OLD.status), NULL);
END$$

-- =====================================================================
-- BOOKING
-- =====================================================================

DROP TRIGGER IF EXISTS trg_booking_bi$$
CREATE TRIGGER trg_booking_bi BEFORE INSERT ON BOOKING FOR EACH ROW
BEGIN
    DECLARE v_fstatus  VARCHAR(20);
    DECLARE v_aircraft INT;
    DECLARE v_dep_date DATE;
    DECLARE v_cap      INT;
    DECLARE v_cnt      INT DEFAULT 0;
    DECLARE v_seat_aircraft INT;
    DECLARE v_seat_active   BOOLEAN;
    DECLARE v_seat_class    VARCHAR(10);
    DECLARE v_expiry   DATE;
    DECLARE v_price    DECIMAL(10,2);
    DECLARE v_ex_id    INT;
    DECLARE v_ex_ref   VARCHAR(10);
    DECLARE v_msg      VARCHAR(128);

    SELECT status, aircraft_id, departure_date
      INTO v_fstatus, v_aircraft, v_dep_date
    FROM FLIGHT WHERE flight_id = NEW.flight_id;

    IF v_fstatus IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Flight not found';
    END IF;
    IF v_fstatus IN ('Cancelled', 'Departed', 'Arrived') THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Bookings are closed: flight is cancelled, departed or arrived';
    END IF;

    IF NEW.booking_status <> 'Cancelled' THEN
        -- overbooking
        SELECT capacity INTO v_cap FROM AIRCRAFT WHERE aircraft_id = v_aircraft;
        SELECT COUNT(*) INTO v_cnt FROM BOOKING
        WHERE flight_id = NEW.flight_id AND booking_status <> 'Cancelled';
        IF v_cnt >= v_cap THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Flight is fully booked';
        END IF;

        -- same passenger twice on one flight
        SELECT booking_id, booking_reference INTO v_ex_id, v_ex_ref FROM BOOKING
        WHERE flight_id = NEW.flight_id AND passenger_id = NEW.passenger_id
          AND booking_status <> 'Cancelled' LIMIT 1;
        IF v_ex_id IS NOT NULL THEN
            SET v_msg = CONCAT('Passenger already has an active booking on this flight (booking id ',
                               v_ex_id, ', PNR ', v_ex_ref, '). Cancel it first or use another passenger');
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
        END IF;

        -- passport must be valid on the travel date
        SELECT passport_expiry INTO v_expiry FROM PASSENGER WHERE passenger_id = NEW.passenger_id;
        IF v_expiry IS NOT NULL AND v_expiry < v_dep_date THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Passenger passport expires before the travel date';
        END IF;
    END IF;

    -- seat rules
    IF NEW.seat_id IS NOT NULL THEN
        SELECT aircraft_id, is_active, `class`
          INTO v_seat_aircraft, v_seat_active, v_seat_class
        FROM SEAT WHERE seat_id = NEW.seat_id;

        IF v_seat_aircraft IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Seat not found';
        END IF;
        IF v_seat_aircraft <> v_aircraft THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Seat does not belong to the aircraft of this flight';
        END IF;
        IF NOT v_seat_active THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Seat is not available (inactive)';
        END IF;

        -- cancelled bookings have seat_id = NULL, so any row means the seat is taken
        SELECT booking_id, booking_reference INTO v_ex_id, v_ex_ref FROM BOOKING
        WHERE flight_id = NEW.flight_id AND seat_id = NEW.seat_id LIMIT 1;
        IF v_ex_id IS NOT NULL THEN
            SET v_msg = CONCAT('Seat is already booked for this flight (booking id ',
                               v_ex_id, ', PNR ', v_ex_ref, ')');
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
        END IF;

        -- auto-fill total_amount from the fare of the seat's class
        IF NEW.total_amount = 0 THEN
            SELECT base_price INTO v_price FROM FLIGHT_FARE
            WHERE flight_id = NEW.flight_id AND `class` = v_seat_class;
            IF v_price IS NULL THEN
                SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'No fare is set for this seat class on this flight. Set the flight fares first';
            END IF;
            SET NEW.total_amount = v_price;
        END IF;
    END IF;
END$$

DROP TRIGGER IF EXISTS trg_booking_ai$$
CREATE TRIGGER trg_booking_ai AFTER INSERT ON BOOKING FOR EACH ROW
BEGIN
    IF NEW.seat_id IS NOT NULL THEN
        UPDATE FLIGHT_FARE ff JOIN SEAT s ON s.`class` = ff.`class`
        SET ff.seats_available = ff.seats_available - 1
        WHERE ff.flight_id = NEW.flight_id AND s.seat_id = NEW.seat_id;
    END IF;

    CALL sp_audit('INSERT', 'BOOKING', NEW.booking_id, NULL,
        JSON_OBJECT('booking_reference', NEW.booking_reference, 'status', NEW.booking_status,
                    'seat_id', NEW.seat_id, 'total_amount', NEW.total_amount));
END$$

DROP TRIGGER IF EXISTS trg_booking_bu$$
CREATE TRIGGER trg_booking_bu BEFORE UPDATE ON BOOKING FOR EACH ROW
BEGIN
    DECLARE v_fstatus  VARCHAR(20);
    DECLARE v_aircraft INT;
    DECLARE v_seat_aircraft INT;
    DECLARE v_seat_active   BOOLEAN;
    DECLARE v_cnt INT DEFAULT 0;

    IF NEW.flight_id <> OLD.flight_id THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Flight cannot be changed on a booking: cancel and rebook instead';
    END IF;

    IF OLD.booking_status = 'Cancelled' AND NEW.booking_status <> 'Cancelled' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'A cancelled booking cannot be reactivated';
    END IF;

    SELECT status, aircraft_id INTO v_fstatus, v_aircraft
    FROM FLIGHT WHERE flight_id = NEW.flight_id;

    -- cancelling: not allowed after departure; frees the seat
    IF OLD.booking_status <> 'Cancelled' AND NEW.booking_status = 'Cancelled' THEN
        IF v_fstatus IN ('Departed', 'Arrived') THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Cannot cancel a booking for a flight that has already departed';
        END IF;
        SET NEW.seat_id = NULL;
    END IF;

    -- changing seat: same checks as on insert
    IF NEW.seat_id IS NOT NULL AND NOT (OLD.seat_id <=> NEW.seat_id) THEN
        SELECT aircraft_id, is_active INTO v_seat_aircraft, v_seat_active
        FROM SEAT WHERE seat_id = NEW.seat_id;

        IF v_seat_aircraft <> v_aircraft THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Seat does not belong to the aircraft of this flight';
        END IF;
        IF NOT v_seat_active THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Seat is not available (inactive)';
        END IF;
        SELECT COUNT(*) INTO v_cnt FROM BOOKING
        WHERE flight_id = NEW.flight_id AND seat_id = NEW.seat_id
          AND booking_id <> NEW.booking_id;
        IF v_cnt > 0 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Seat is already booked for this flight';
        END IF;
    END IF;
END$$

DROP TRIGGER IF EXISTS trg_booking_au$$
CREATE TRIGGER trg_booking_au AFTER UPDATE ON BOOKING FOR EACH ROW
BEGIN
    DECLARE v_fstatus VARCHAR(20);
    DECLARE v_paid    DECIMAL(10,2) DEFAULT 0;
    DECLARE v_user    INT;

    -- keep FLIGHT_FARE.seats_available in sync when the seat changes / is freed
    IF NOT (OLD.seat_id <=> NEW.seat_id) THEN
        IF OLD.seat_id IS NOT NULL THEN
            UPDATE FLIGHT_FARE ff JOIN SEAT s ON s.`class` = ff.`class`
            SET ff.seats_available = ff.seats_available + 1
            WHERE ff.flight_id = OLD.flight_id AND s.seat_id = OLD.seat_id;
        END IF;
        IF NEW.seat_id IS NOT NULL THEN
            UPDATE FLIGHT_FARE ff JOIN SEAT s ON s.`class` = ff.`class`
            SET ff.seats_available = ff.seats_available - 1
            WHERE ff.flight_id = NEW.flight_id AND s.seat_id = NEW.seat_id;
        END IF;
    END IF;

    -- on cancellation: cancel ticket, refund payments, record CANCELLATION
    IF OLD.booking_status <> 'Cancelled' AND NEW.booking_status = 'Cancelled' THEN
        SELECT status INTO v_fstatus FROM FLIGHT WHERE flight_id = NEW.flight_id;

        SELECT COALESCE(SUM(p.amount), 0) INTO v_paid
        FROM PAYMENT p JOIN TICKET t ON t.ticket_id = p.ticket_id
        WHERE t.booking_id = NEW.booking_id AND p.status = 'Success';

        UPDATE TICKET SET status = 'Cancelled'
        WHERE booking_id = NEW.booking_id AND status = 'Issued';

        UPDATE PAYMENT p JOIN TICKET t ON t.ticket_id = p.ticket_id
        SET p.status = 'Refunded'
        WHERE t.booking_id = NEW.booking_id AND p.status = 'Success';

        SELECT user_id INTO v_user FROM USER_ACCOUNT WHERE user_id = @app_user_id;

        -- refund policy: 100% if the airline cancelled, otherwise 80%
        INSERT INTO CANCELLATION (booking_id, reason, refund_amount, processed_by)
        SELECT NEW.booking_id,
               IF(v_fstatus = 'Cancelled', 'Flight cancelled by airline', 'Cancelled by passenger'),
               IF(v_fstatus = 'Cancelled', v_paid, ROUND(v_paid * 0.8, 2)),
               v_user
        WHERE NOT EXISTS (SELECT 1 FROM CANCELLATION WHERE booking_id = NEW.booking_id);
    END IF;

    CALL sp_audit('UPDATE', 'BOOKING', NEW.booking_id,
        JSON_OBJECT('status', OLD.booking_status, 'seat_id', OLD.seat_id),
        JSON_OBJECT('status', NEW.booking_status, 'seat_id', NEW.seat_id));
END$$

DROP TRIGGER IF EXISTS trg_booking_ad$$
CREATE TRIGGER trg_booking_ad AFTER DELETE ON BOOKING FOR EACH ROW
BEGIN
    IF OLD.seat_id IS NOT NULL THEN
        UPDATE FLIGHT_FARE ff JOIN SEAT s ON s.`class` = ff.`class`
        SET ff.seats_available = ff.seats_available + 1
        WHERE ff.flight_id = OLD.flight_id AND s.seat_id = OLD.seat_id;
    END IF;
    CALL sp_audit('DELETE', 'BOOKING', OLD.booking_id,
        JSON_OBJECT('booking_reference', OLD.booking_reference, 'status', OLD.booking_status), NULL);
END$$

-- =====================================================================
-- TICKET
-- =====================================================================

DROP TRIGGER IF EXISTS trg_ticket_bi$$
CREATE TRIGGER trg_ticket_bi BEFORE INSERT ON TICKET FOR EACH ROW
BEGIN
    DECLARE v_bstatus VARCHAR(20);
    SELECT booking_status INTO v_bstatus FROM BOOKING WHERE booking_id = NEW.booking_id;
    IF v_bstatus = 'Cancelled' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Cannot issue a ticket for a cancelled booking';
    END IF;
END$$

DROP TRIGGER IF EXISTS trg_ticket_ai$$
CREATE TRIGGER trg_ticket_ai AFTER INSERT ON TICKET FOR EACH ROW
BEGIN
    UPDATE BOOKING SET booking_status = 'Confirmed'
    WHERE booking_id = NEW.booking_id AND booking_status = 'Pending';
END$$

-- =====================================================================
-- PAYMENT
-- =====================================================================

DROP TRIGGER IF EXISTS trg_payment_bi$$
CREATE TRIGGER trg_payment_bi BEFORE INSERT ON PAYMENT FOR EACH ROW
BEGIN
    DECLARE v_tstatus VARCHAR(20);
    DECLARE v_fare    DECIMAL(10,2);
    DECLARE v_paid    DECIMAL(10,2) DEFAULT 0;

    SELECT status, fare_amount INTO v_tstatus, v_fare
    FROM TICKET WHERE ticket_id = NEW.ticket_id;

    IF v_tstatus <> 'Issued' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Payments are only allowed for issued tickets';
    END IF;

    IF NEW.status = 'Success' THEN
        SELECT COALESCE(SUM(amount), 0) INTO v_paid FROM PAYMENT
        WHERE ticket_id = NEW.ticket_id AND status = 'Success';
        IF v_paid + NEW.amount > v_fare THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Payment exceeds the ticket fare';
        END IF;
    END IF;
END$$

DROP TRIGGER IF EXISTS trg_payment_ai$$
CREATE TRIGGER trg_payment_ai AFTER INSERT ON PAYMENT FOR EACH ROW
BEGIN
    CALL sp_audit('INSERT', 'PAYMENT', NEW.payment_id, NULL,
        JSON_OBJECT('amount', NEW.amount, 'status', NEW.status,
                    'payment_mode', NEW.payment_mode, 'ticket_id', NEW.ticket_id));
END$$

DROP TRIGGER IF EXISTS trg_payment_au$$
CREATE TRIGGER trg_payment_au AFTER UPDATE ON PAYMENT FOR EACH ROW
BEGIN
    CALL sp_audit('UPDATE', 'PAYMENT', NEW.payment_id,
        JSON_OBJECT('status', OLD.status, 'amount', OLD.amount),
        JSON_OBJECT('status', NEW.status, 'amount', NEW.amount));
END$$

-- =====================================================================
-- BAGGAGE
-- =====================================================================

DROP TRIGGER IF EXISTS trg_baggage_bi$$
CREATE TRIGGER trg_baggage_bi BEFORE INSERT ON BAGGAGE FOR EACH ROW
BEGIN
    DECLARE v_bstatus VARCHAR(20);
    SELECT booking_status INTO v_bstatus FROM BOOKING WHERE booking_id = NEW.booking_id;
    IF v_bstatus = 'Cancelled' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Cannot add baggage to a cancelled booking';
    END IF;

    IF NEW.baggage_type = 'Checked' THEN
        IF NEW.weight > 32 THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Checked baggage cannot exceed 32 kg per bag';
        END IF;
        -- 15 kg free, Rs.100 per extra kg
        SET NEW.fee = IF(NEW.weight > 15, (NEW.weight - 15) * 100, 0);
    ELSE
        IF NEW.weight > 7 THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Cabin baggage cannot exceed 7 kg';
        END IF;
        SET NEW.fee = 0;
    END IF;
END$$

-- =====================================================================
-- CHECK_IN
-- =====================================================================

DROP TRIGGER IF EXISTS trg_checkin_bi$$
CREATE TRIGGER trg_checkin_bi BEFORE INSERT ON CHECK_IN FOR EACH ROW
BEGIN
    DECLARE v_tstatus VARCHAR(20);
    DECLARE v_fstatus VARCHAR(20);

    SELECT t.status, f.status INTO v_tstatus, v_fstatus
    FROM TICKET t
    JOIN BOOKING b ON b.booking_id = t.booking_id
    JOIN FLIGHT f  ON f.flight_id = b.flight_id
    WHERE t.ticket_id = NEW.ticket_id;

    IF v_tstatus <> 'Issued' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Check-in requires an issued (not cancelled) ticket';
    END IF;
    IF v_fstatus IN ('Cancelled', 'Departed', 'Arrived') THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Check-in closed: flight is cancelled, departed or arrived';
    END IF;
END$$

DROP TRIGGER IF EXISTS trg_checkin_bu$$
CREATE TRIGGER trg_checkin_bu BEFORE UPDATE ON CHECK_IN FOR EACH ROW
BEGIN
    IF NEW.boarding_status = 'Boarded' AND NEW.boarding_time IS NULL THEN
        SET NEW.boarding_time = NOW();
    END IF;
END$$

-- =====================================================================
-- PASSENGER (audit only)
-- =====================================================================

DROP TRIGGER IF EXISTS trg_passenger_ai$$
CREATE TRIGGER trg_passenger_ai AFTER INSERT ON PASSENGER FOR EACH ROW
BEGIN
    CALL sp_audit('INSERT', 'PASSENGER', NEW.passenger_id, NULL,
        JSON_OBJECT('name', CONCAT(NEW.first_name, ' ', IFNULL(NEW.last_name, '')),
                    'passport_no', NEW.passport_no));
END$$

DROP TRIGGER IF EXISTS trg_passenger_au$$
CREATE TRIGGER trg_passenger_au AFTER UPDATE ON PASSENGER FOR EACH ROW
BEGIN
    CALL sp_audit('UPDATE', 'PASSENGER', NEW.passenger_id,
        JSON_OBJECT('phone_no', OLD.phone_no, 'email', OLD.email, 'passport_no', OLD.passport_no),
        JSON_OBJECT('phone_no', NEW.phone_no, 'email', NEW.email, 'passport_no', NEW.passport_no));
END$$

DROP TRIGGER IF EXISTS trg_passenger_ad$$
CREATE TRIGGER trg_passenger_ad AFTER DELETE ON PASSENGER FOR EACH ROW
BEGIN
    CALL sp_audit('DELETE', 'PASSENGER', OLD.passenger_id,
        JSON_OBJECT('name', CONCAT(OLD.first_name, ' ', IFNULL(OLD.last_name, '')),
                    'passport_no', OLD.passport_no), NULL);
END$$

DELIMITER ;

SHOW TRIGGERS;

-- =====================================================================
-- QUICK TESTS (run one at a time; expected result in the comment)
-- =====================================================================
-- SET @app_user_id = 1;
--
-- 1) Seat already taken -> ERROR "Seat is already booked for this flight"
-- INSERT INTO BOOKING (booking_reference, passenger_id, flight_id, seat_id, booked_by)
-- VALUES ('TEST0001', 28, 1, (SELECT seat_id FROM SEAT WHERE aircraft_id = 1 AND seat_no = '1A'), 1);
--
-- 2) Free seat -> OK, total_amount auto-filled, seats_available drops by 1
-- INSERT INTO BOOKING (booking_reference, passenger_id, flight_id, seat_id, booked_by)
-- VALUES ('TEST0002', 28, 1, (SELECT seat_id FROM SEAT WHERE aircraft_id = 1 AND seat_no = '2A'), 1);
-- SELECT * FROM BOOKING WHERE booking_reference = 'TEST0002';
-- SELECT * FROM FLIGHT_FARE WHERE flight_id = 1;
--
-- 3) Cancel it -> seat_id becomes NULL, CANCELLATION row created, seats_available restored
-- UPDATE BOOKING SET booking_status = 'Cancelled' WHERE booking_reference = 'TEST0002';
-- SELECT * FROM CANCELLATION ORDER BY cancel_id DESC LIMIT 1;
--
-- 4) Same source and destination -> ERROR
-- INSERT INTO FLIGHT (flight_no, departure_date, departure_time, arrival_date, arrival_time,
--                     airline_id, aircraft_id, source_airport_id, destination_airport_id, gate_id)
-- VALUES ('XX900', '2026-11-01', '10:00', '2026-11-01', '12:00', 1, 8, 1, 1, 1);
--
-- 5) Gate conflict (gate 1 has AI101 at 06:00) -> ERROR "Gate is already allocated..."
-- INSERT INTO FLIGHT (flight_no, departure_date, departure_time, arrival_date, arrival_time,
--                     airline_id, aircraft_id, source_airport_id, destination_airport_id, gate_id)
-- VALUES ('XX999', '2026-10-10', '06:30', '2026-10-10', '08:00', 1, 8, 1, 2, 1);
--
-- 6) Cancel a whole flight -> all its bookings cancelled, 100% refunds
-- UPDATE FLIGHT SET status = 'Cancelled' WHERE flight_no = 'AI111';
--
-- 7) Check the audit trail
-- SELECT * FROM AUDIT_LOG ORDER BY log_id DESC LIMIT 20;
