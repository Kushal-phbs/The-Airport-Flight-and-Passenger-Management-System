-- =====================================================================
-- Airport Flight and Passenger Management System
-- procedures.sql -- run AFTER schema.sql, seed_data.sql and triggers.sql
-- Re-runnable: each procedure is dropped before it is created.
--
-- These are the procedures the Flask API will call.
-- Each write procedure takes p_user_id and sets @app_user_id so the
-- triggers can record who made the change in AUDIT_LOG.
-- =====================================================================
USE airport_db;

DELIMITER $$

-- =====================================================================
-- 1. sp_book_ticket : booking + ticket + payment in ONE transaction
--    Triggers validate seat, capacity, duplicate passenger, passport, etc.
--    Any error rolls everything back and is re-raised to the caller.
-- =====================================================================
DROP PROCEDURE IF EXISTS sp_book_ticket$$
CREATE PROCEDURE sp_book_ticket(
    IN  p_passenger_id  INT,
    IN  p_flight_id     INT,
    IN  p_seat_no       VARCHAR(5),
    IN  p_payment_mode  VARCHAR(20),     -- Card / UPI / NetBanking / Cash
    IN  p_user_id       INT,
    OUT p_booking_id    INT,
    OUT p_ticket_no     VARCHAR(20),
    OUT p_pnr           VARCHAR(10))
BEGIN
    DECLARE v_flight  INT;
    DECLARE v_seat_id INT;
    DECLARE v_fare    DECIMAL(10,2);
    DECLARE v_ticket_id INT;
    DECLARE v_cnt     INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    SET @app_user_id = p_user_id;

    START TRANSACTION;

    -- lock the flight row so two agents cannot grab the same seat / last seat
    SELECT flight_id INTO v_flight FROM FLIGHT WHERE flight_id = p_flight_id FOR UPDATE;
    IF v_flight IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Flight not found';
    END IF;

    -- resolve seat number -> seat_id on this flight's aircraft
    SELECT s.seat_id INTO v_seat_id
    FROM SEAT s JOIN FLIGHT f ON f.aircraft_id = s.aircraft_id
    WHERE f.flight_id = p_flight_id AND s.seat_no = p_seat_no;
    IF v_seat_id IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Invalid seat number for this flight';
    END IF;

    -- unique PNR
    REPEAT
        SET p_pnr = CONCAT('PNR', UPPER(SUBSTRING(REPLACE(UUID(), '-', ''), 1, 6)));
        SELECT COUNT(*) INTO v_cnt FROM BOOKING WHERE booking_reference = p_pnr;
    UNTIL v_cnt = 0 END REPEAT;

    -- booking (trigger auto-fills total_amount from the seat's class fare)
    INSERT INTO BOOKING (booking_reference, booking_status, passenger_id, flight_id, seat_id, booked_by)
    VALUES (p_pnr, 'Pending', p_passenger_id, p_flight_id, v_seat_id, p_user_id);
    SET p_booking_id = LAST_INSERT_ID();

    SELECT total_amount INTO v_fare FROM BOOKING WHERE booking_id = p_booking_id;

    -- ticket (trigger moves the booking to Confirmed)
    SET p_ticket_no = CONCAT('TKT', LPAD(p_booking_id, 8, '0'));
    INSERT INTO TICKET (ticket_no, fare_amount, booking_id)
    VALUES (p_ticket_no, v_fare, p_booking_id);
    SET v_ticket_id = LAST_INSERT_ID();

    -- payment
    INSERT INTO PAYMENT (amount, payment_mode, transaction_id, status, ticket_id)
    VALUES (v_fare, p_payment_mode,
            CONCAT('TXN', UPPER(SUBSTRING(REPLACE(UUID(), '-', ''), 1, 12))), 'Success', v_ticket_id);

    COMMIT;
END$$

-- =====================================================================
-- 2. sp_cancel_booking : cancel + refund (the booking trigger does the work:
--    frees seat, cancels ticket, marks payments Refunded, creates CANCELLATION)
--    Refund = 100% if the airline cancelled the flight, else 80%.
-- =====================================================================
DROP PROCEDURE IF EXISTS sp_cancel_booking$$
CREATE PROCEDURE sp_cancel_booking(
    IN  p_booking_id INT,
    IN  p_reason     VARCHAR(255),
    IN  p_user_id    INT,
    OUT p_refund     DECIMAL(10,2))
BEGIN
    DECLARE v_status VARCHAR(20);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    SET @app_user_id = p_user_id;

    SELECT booking_status INTO v_status FROM BOOKING WHERE booking_id = p_booking_id;
    IF v_status IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Booking not found';
    END IF;
    IF v_status = 'Cancelled' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Booking is already cancelled';
    END IF;

    START TRANSACTION;

    UPDATE BOOKING SET booking_status = 'Cancelled' WHERE booking_id = p_booking_id;

    IF p_reason IS NOT NULL AND p_reason <> '' THEN
        UPDATE CANCELLATION SET reason = p_reason WHERE booking_id = p_booking_id;
    END IF;

    SELECT refund_amount INTO p_refund FROM CANCELLATION WHERE booking_id = p_booking_id;

    COMMIT;
END$$

-- =====================================================================
-- 3. sp_get_flight_manifest : passenger list for one flight
-- =====================================================================
DROP PROCEDURE IF EXISTS sp_get_flight_manifest$$
CREATE PROCEDURE sp_get_flight_manifest(IN p_flight_id INT)
BEGIN
    SELECT b.booking_id,
           b.booking_reference,
           CONCAT(p.first_name, ' ', IFNULL(p.last_name, '')) AS passenger_name,
           p.passport_no,
           s.seat_no,
           s.`class`,
           b.booking_status,
           t.ticket_no,
           COALESCE(ci.boarding_status, 'Not Checked-In') AS check_in_status,
           COUNT(bg.baggage_id)           AS bags,
           COALESCE(SUM(bg.weight), 0)    AS total_baggage_kg
    FROM BOOKING b
    JOIN PASSENGER p        ON p.passenger_id = b.passenger_id
    LEFT JOIN SEAT s        ON s.seat_id = b.seat_id
    LEFT JOIN TICKET t      ON t.booking_id = b.booking_id AND t.status = 'Issued'
    LEFT JOIN CHECK_IN ci   ON ci.ticket_id = t.ticket_id
    LEFT JOIN BAGGAGE bg    ON bg.booking_id = b.booking_id
    WHERE b.flight_id = p_flight_id
      AND b.booking_status <> 'Cancelled'
    GROUP BY b.booking_id, b.booking_reference, b.booking_status,
             p.passenger_id, p.first_name, p.last_name, p.passport_no,
             s.seat_id, s.seat_no, s.`class`,
             t.ticket_id, t.ticket_no, ci.checkin_id, ci.boarding_status
    ORDER BY CAST(s.seat_no AS UNSIGNED), s.seat_no;
END$$

-- =====================================================================
-- 4. sp_check_in : check a passenger in using the ticket number
-- =====================================================================
DROP PROCEDURE IF EXISTS sp_check_in$$
CREATE PROCEDURE sp_check_in(
    IN  p_ticket_no  VARCHAR(20),
    IN  p_user_id    INT,
    OUT p_checkin_id INT)
BEGIN
    DECLARE v_ticket_id INT;

    SET @app_user_id = p_user_id;

    SELECT ticket_id INTO v_ticket_id FROM TICKET WHERE ticket_no = p_ticket_no;
    IF v_ticket_id IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Ticket not found';
    END IF;

    -- trigger rejects cancelled tickets and flights that are closed
    INSERT INTO CHECK_IN (ticket_id) VALUES (v_ticket_id);
    SET p_checkin_id = LAST_INSERT_ID();
END$$

-- =====================================================================
-- 5. sp_board_passenger : mark a checked-in passenger as boarded
-- =====================================================================
DROP PROCEDURE IF EXISTS sp_board_passenger$$
CREATE PROCEDURE sp_board_passenger(IN p_ticket_no VARCHAR(20), IN p_user_id INT)
BEGIN
    DECLARE v_rows INT;

    SET @app_user_id = p_user_id;

    UPDATE CHECK_IN ci JOIN TICKET t ON t.ticket_id = ci.ticket_id
    SET ci.boarding_status = 'Boarded'
    WHERE t.ticket_no = p_ticket_no;

    SET v_rows = ROW_COUNT();
    IF v_rows = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Passenger has not checked in (or ticket not found)';
    END IF;
END$$

-- =====================================================================
-- 6. sp_search_flights : search by airport codes and/or date
--    Pass NULL or '' for any filter you do not want.
-- =====================================================================
DROP PROCEDURE IF EXISTS sp_search_flights$$
CREATE PROCEDURE sp_search_flights(
    IN p_src  VARCHAR(10),
    IN p_dst  VARCHAR(10),
    IN p_date DATE)
BEGIN
    SELECT f.flight_id,
           f.flight_no,
           al.airline_name,
           sa.airport_code AS source,
           da.airport_code AS destination,
           f.departure_date, f.departure_time,
           f.arrival_date,   f.arrival_time,
           f.status, f.delay_minutes,
           g.terminal, g.gate_no,
           fe.base_price AS economy_fare,  fe.seats_available AS economy_seats,
           fb.base_price AS business_fare, fb.seats_available AS business_seats
    FROM FLIGHT f
    JOIN AIRLINE al  ON al.airline_id = f.airline_id
    JOIN AIRPORT sa  ON sa.airport_id = f.source_airport_id
    JOIN AIRPORT da  ON da.airport_id = f.destination_airport_id
    LEFT JOIN GATE g ON g.gate_id = f.gate_id
    LEFT JOIN FLIGHT_FARE fe ON fe.flight_id = f.flight_id AND fe.`class` = 'Economy'
    LEFT JOIN FLIGHT_FARE fb ON fb.flight_id = f.flight_id AND fb.`class` = 'Business'
    WHERE (p_src  IS NULL OR p_src  = '' OR sa.airport_code = p_src)
      AND (p_dst  IS NULL OR p_dst  = '' OR da.airport_code = p_dst)
      AND (p_date IS NULL OR f.departure_date = p_date)
    ORDER BY f.departure_date, f.departure_time;
END$$

-- =====================================================================
-- 7. sp_seat_map : every seat of the flight's aircraft with taken flag
--    (used by the seat-selection screen)
-- =====================================================================
DROP PROCEDURE IF EXISTS sp_seat_map$$
CREATE PROCEDURE sp_seat_map(IN p_flight_id INT)
BEGIN
    SELECT s.seat_id, s.seat_no, s.`class`, s.seat_type, s.is_active,
           (b.booking_id IS NOT NULL) AS is_taken
    FROM FLIGHT f
    JOIN SEAT s ON s.aircraft_id = f.aircraft_id
    LEFT JOIN BOOKING b ON b.flight_id = f.flight_id AND b.seat_id = s.seat_id
    WHERE f.flight_id = p_flight_id
    ORDER BY CAST(s.seat_no AS UNSIGNED), s.seat_no;
END$$

-- =====================================================================
-- 8. sp_dashboard_stats : one row of headline numbers for the dashboard
-- =====================================================================
DROP PROCEDURE IF EXISTS sp_dashboard_stats$$
CREATE PROCEDURE sp_dashboard_stats()
BEGIN
    SELECT
        (SELECT COUNT(*) FROM FLIGHT)                                          AS total_flights,
        (SELECT COUNT(*) FROM FLIGHT
          WHERE status IN ('Scheduled', 'Boarding', 'Delayed')
            AND departure_date >= CURDATE())                                   AS upcoming_flights,
        (SELECT COUNT(*) FROM FLIGHT WHERE status = 'Delayed')                 AS delayed_flights,
        (SELECT COUNT(*) FROM FLIGHT WHERE status = 'Cancelled')               AS cancelled_flights,
        (SELECT COUNT(*) FROM PASSENGER)                                       AS total_passengers,
        (SELECT COUNT(*) FROM BOOKING WHERE booking_status <> 'Cancelled')     AS active_bookings,
        (SELECT COUNT(*) FROM BOOKING WHERE booking_status = 'Cancelled')      AS cancelled_bookings,
        (SELECT COUNT(*) FROM TICKET WHERE status = 'Issued')                  AS tickets_issued,
        (SELECT COALESCE(SUM(amount), 0) FROM PAYMENT WHERE status = 'Success') AS total_revenue;
END$$

DELIMITER ;

SHOW PROCEDURE STATUS WHERE Db = 'airport_db';

-- =====================================================================
-- QUICK TESTS (run one at a time)
-- =====================================================================
-- 1) Book: passenger 28 on flight 1, seat 3A (Business)
-- CALL sp_book_ticket(28, 1, '3A', 'UPI', 2, @bid, @tkt, @pnr);
-- SELECT @bid, @tkt, @pnr;
--
-- 2) Same seat again -> ERROR "Seat is already booked for this flight" (nothing is saved)
-- CALL sp_book_ticket(29, 1, '3A', 'Card', 2, @bid2, @tkt2, @pnr2);
--
-- 3) Cancel it -> refund = 80% of the fare
-- CALL sp_cancel_booking(@bid, 'Change of plans', 2, @refund);
-- SELECT @refund;
--
-- 4) Manifest, seat map, search, dashboard
-- CALL sp_get_flight_manifest(1);
-- CALL sp_seat_map(1);
-- CALL sp_search_flights('MAA', 'DEL', '2026-10-10');
-- CALL sp_dashboard_stats();
--
-- 5) Check-in and board a ticket (use a real ticket_no from the manifest)
-- CALL sp_check_in('TKT00000001', 2, @cid);
-- CALL sp_board_passenger('TKT00000001', 2);
