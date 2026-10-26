-- =====================================================================
-- Airport Flight and Passenger Management System
-- seed_data.sql  -- run AFTER schema.sql, and BEFORE triggers.sql
-- (assumes a freshly created airport_db so AUTO_INCREMENT ids start at 1)
-- =====================================================================
USE airport_db;
SET SQL_SAFE_UPDATES = 0;

-- ---------------------------------------------------------------------
-- USERS  (login: admin/admin123, staff1/staff123, agent1/agent123)
-- Hashes are werkzeug pbkdf2:sha256, so Flask's check_password_hash works.
-- ---------------------------------------------------------------------
INSERT INTO USER_ACCOUNT (username, password_hash, role, email) VALUES
('admin',  'pbkdf2:sha256:1000000$KA4P82CzK3qgYxaE$d7080dd7f5d809cf18dc21fb64c982d888c30a60c879c575a1f7a191c4a52f63', 'Admin', 'admin@airport.com'),
('staff1', 'pbkdf2:sha256:1000000$9oSCVDZaJ97ZK7ep$86f59a6b6a7dfb111690c5f979e82b7906627da683eb0b37da8538658770d08c', 'Staff', 'staff1@airport.com'),
('agent1', 'pbkdf2:sha256:1000000$Ey4ElEV8PFGvaAG6$d02088dddc4177661af6413935a8543f550c77bf364538b15c9ef09246d5a10e', 'Agent', 'agent1@airport.com');

-- ---------------------------------------------------------------------
-- AIRLINES
-- ---------------------------------------------------------------------
INSERT INTO AIRLINE (airline_name, airline_code, country, contact_no, email) VALUES
('Air India',          'AI', 'India',     '1800-180-1407', 'care@airindia.example'),
('IndiGo',             '6E', 'India',     '0124-6173838',  'care@indigo.example'),
('SpiceJet',           'SG', 'India',     '0124-4983410',  'care@spicejet.example'),
('Emirates',           'EK', 'UAE',       '+971-600-555555','care@emirates.example'),
('Singapore Airlines', 'SQ', 'Singapore', '+65-6223-8888', 'care@singaporeair.example');

-- ---------------------------------------------------------------------
-- AIRPORTS (ids 1-10)
-- ---------------------------------------------------------------------
INSERT INTO AIRPORT (airport_name, city, country, airport_code, timezone) VALUES
('Chennai International Airport',            'Chennai',   'India',     'MAA', 'Asia/Kolkata'),
('Indira Gandhi International Airport',      'Delhi',     'India',     'DEL', 'Asia/Kolkata'),
('Chhatrapati Shivaji Maharaj Intl Airport', 'Mumbai',    'India',     'BOM', 'Asia/Kolkata'),
('Kempegowda International Airport',         'Bengaluru', 'India',     'BLR', 'Asia/Kolkata'),
('Rajiv Gandhi International Airport',       'Hyderabad', 'India',     'HYD', 'Asia/Kolkata'),
('Netaji Subhas Chandra Bose Intl Airport',  'Kolkata',   'India',     'CCU', 'Asia/Kolkata'),
('Dubai International Airport',              'Dubai',     'UAE',       'DXB', 'Asia/Dubai'),
('Changi Airport',                           'Singapore', 'Singapore', 'SIN', 'Asia/Singapore'),
('Heathrow Airport',                         'London',    'UK',        'LHR', 'Europe/London'),
('John F. Kennedy International Airport',    'New York',  'USA',       'JFK', 'America/New_York');

-- ---------------------------------------------------------------------
-- GATES: 3 per airport (ids 1-3 MAA, 4-6 DEL, 7-9 BOM, ... 28-30 JFK)
-- ---------------------------------------------------------------------
INSERT INTO GATE (gate_no, terminal, airport_id)
SELECT g.gate_no, g.terminal, a.airport_id
FROM AIRPORT a
CROSS JOIN (SELECT 'A1' AS gate_no, 'T1' AS terminal
            UNION ALL SELECT 'A2', 'T1'
            UNION ALL SELECT 'B1', 'T2') g
ORDER BY a.airport_id, g.gate_no;

-- ---------------------------------------------------------------------
-- AIRCRAFT (ids 1-8). Capacity simplified to 120 seats each (20 rows x 6).
-- ---------------------------------------------------------------------
INSERT INTO AIRCRAFT (aircraft_code, model, manufacturer, year_of_manufacture, capacity, status, airline_id) VALUES
('VT-AI01', 'A320',     'Airbus', 2016, 120, 'Active', 1),
('VT-AI02', 'A321',     'Airbus', 2018, 120, 'Active', 1),
('VT-IG01', 'A320neo',  'Airbus', 2020, 120, 'Active', 2),
('VT-IG02', 'A320neo',  'Airbus', 2021, 120, 'Active', 2),
('VT-SG01', '737-800',  'Boeing', 2015, 120, 'Active', 3),
('A6-EK01', 'A330-200', 'Airbus', 2017, 120, 'Active', 4),
('9V-SQ01', 'A350-900', 'Airbus', 2019, 120, 'Active', 5),
('VT-AI03', '737-800',  'Boeing', 2014, 120, 'Active', 1);

-- ---------------------------------------------------------------------
-- SEATS: rows 1-3 Business (18 seats), rows 4-20 Economy (102 seats)
-- A/F = Window, C/D = Aisle, B/E = Middle
-- ---------------------------------------------------------------------
INSERT INTO SEAT (aircraft_id, seat_no, `class`, seat_type)
SELECT a.aircraft_id,
       CONCAT(r.n, l.letter),
       IF(r.n <= 3, 'Business', 'Economy'),
       CASE WHEN l.letter IN ('A','F') THEN 'Window'
            WHEN l.letter IN ('C','D') THEN 'Aisle'
            ELSE 'Middle' END
FROM AIRCRAFT a
CROSS JOIN (SELECT t.d*10 + o.d + 1 AS n
            FROM (SELECT 0 AS d UNION ALL SELECT 1 UNION ALL SELECT 2) t
            CROSS JOIN (SELECT 0 AS d UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3
                        UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6
                        UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) o) r
CROSS JOIN (SELECT 'A' AS letter UNION ALL SELECT 'B' UNION ALL SELECT 'C'
            UNION ALL SELECT 'D' UNION ALL SELECT 'E' UNION ALL SELECT 'F') l
WHERE r.n <= 20
ORDER BY a.aircraft_id, r.n, l.letter;

-- ---------------------------------------------------------------------
-- CREW (ids 1-16)
-- ---------------------------------------------------------------------
INSERT INTO CREW (first_name, last_name, role, license_no, phone_no, airline_id) VALUES
('Rajesh',  'Menon',   'Pilot',     'LIC-AI-001', '9810000001', 1),
('Priya',   'Nair',    'Co-Pilot',  'LIC-AI-002', '9810000002', 1),
('Anita',   'Das',     'Attendant', NULL,         '9810000003', 1),
('Vikram',  'Singh',   'Attendant', NULL,         '9810000004', 1),
('Sanjay',  'Kapoor',  'Pilot',     'LIC-6E-001', '9820000001', 2),
('Neha',    'Arora',   'Co-Pilot',  'LIC-6E-002', '9820000002', 2),
('Kiran',   'Rao',     'Attendant', NULL,         '9820000003', 2),
('Amit',    'Bhatt',   'Pilot',     'LIC-SG-001', '9830000001', 3),
('Rhea',    'Kulkarni','Co-Pilot',  'LIC-SG-002', '9830000002', 3),
('Tina',    'Dsouza',  'Attendant', NULL,         '9830000003', 3),
('Omar',    'Haddad',  'Pilot',     'LIC-EK-001', '971500001', 4),
('Layla',   'Saeed',   'Co-Pilot',  'LIC-EK-002', '971500002', 4),
('Zara',    'Ali',     'Attendant', NULL,         '971500003', 4),
('Tan',     'Wei Ming','Pilot',     'LIC-SQ-001', '6581000001', 5),
('Grace',   'Lim',     'Co-Pilot',  'LIC-SQ-002', '6581000002', 5),
('Siti',    'Rahman',  'Attendant', NULL,         '6581000003', 5);

-- ---------------------------------------------------------------------
-- PASSENGERS (ids 1-30)
-- ---------------------------------------------------------------------
INSERT INTO PASSENGER (first_name, last_name, dob, gender, nationality, passport_no, passport_expiry, phone_no, email, address) VALUES
('Arjun',    'Krishnan',     '1990-04-12', 'Male',   'Indian',     'P1000001', '2031-05-20', '+919840011111', 'arjun.krishnan@example.com',  'Anna Nagar, Chennai'),
('Meena',    'Iyer',         '1988-09-23', 'Female', 'Indian',     'P1000002', '2030-08-14', '+919840022222', 'meena.iyer@example.com',       'T Nagar, Chennai'),
('Rahul',    'Sharma',       '1985-01-30', 'Male',   'Indian',     'P1000003', '2032-02-11', '+919810033333', 'rahul.sharma@example.com',     'Dwarka, Delhi'),
('Sneha',    'Reddy',        '1995-06-18', 'Female', 'Indian',     'P1000004', '2029-11-05', '+919848044444', 'sneha.reddy@example.com',      'Banjara Hills, Hyderabad'),
('Karthik',  'Raman',        '1992-12-02', 'Male',   'Indian',     'P1000005', '2031-03-27', '+919840055555', 'karthik.raman@example.com',    'Adyar, Chennai'),
('Divya',    'Menon',        '1993-03-09', 'Female', 'Indian',     'P1000006', '2030-07-19', '+919880066666', 'divya.menon@example.com',      'Indiranagar, Bengaluru'),
('Aman',     'Verma',        '1987-07-21', 'Male',   'Indian',     'P1000007', '2033-01-08', '+919810077777', 'aman.verma@example.com',       'Saket, Delhi'),
('Pooja',    'Patel',        '1991-10-14', 'Female', 'Indian',     'P1000008', '2031-09-30', '+919820088888', 'pooja.patel@example.com',      'Andheri, Mumbai'),
('Suresh',   'Kumar',        '1980-05-05', 'Male',   'Indian',     'P1000009', '2029-12-15', '+919840099999', 'suresh.kumar@example.com',     'Velachery, Chennai'),
('Fatima',   'Khan',         '1994-02-17', 'Female', 'Indian',     'P1000010', '2032-06-22', '+919848010101', 'fatima.khan@example.com',      'Charminar, Hyderabad'),
('Mohammed', 'Rafi',         '1983-11-11', 'Male',   'Indian',     'P1000011', '2030-04-04', '+919820011112', 'mohammed.rafi@example.com',    'Bandra, Mumbai'),
('Lakshmi',  'Narayanan',    '1979-08-08', 'Female', 'Indian',     'P1000012', '2031-10-10', '+919840012121', 'lakshmi.n@example.com',        'Mylapore, Chennai'),
('Vivek',    'Anand',        '1996-01-25', 'Male',   'Indian',     'P1000013', '2033-03-03', '+919880013131', 'vivek.anand@example.com',      'Koramangala, Bengaluru'),
('Ananya',   'Das',          '1997-04-30', 'Female', 'Indian',     'P1000014', '2032-12-12', '+919830014141', 'ananya.das@example.com',       'Salt Lake, Kolkata'),
('Rohit',    'Gupta',        '1989-09-09', 'Male',   'Indian',     'P1000015', '2030-05-05', '+919810015151', 'rohit.gupta@example.com',      'Rohini, Delhi'),
('Nisha',    'Joseph',       '1990-12-20', 'Female', 'Indian',     'P1000016', '2031-01-18', '+919847016161', 'nisha.joseph@example.com',     'Kakkanad, Kochi'),
('Sanjay',   'Mehta',        '1975-06-06', 'Male',   'Indian',     'P1000017', '2029-09-09', '+919820017171', 'sanjay.mehta@example.com',     'Juhu, Mumbai'),
('Emily',    'Carter',       '1991-03-15', 'Female', 'British',    'B2000018', '2031-06-06', '+447700018181', 'emily.carter@example.com',     'Camden, London'),
('David',    'Wilson',       '1984-08-28', 'Male',   'American',   'U3000019', '2032-04-14', '+12125019191',  'david.wilson@example.com',     'Brooklyn, New York'),
('Harini',   'Subramanian',  '1998-02-02', 'Female', 'Indian',     'P1000020', '2033-07-07', '+919840020202', 'harini.s@example.com',         'Nungambakkam, Chennai'),
('Prakash',  'Rao',          '1982-10-31', 'Male',   'Indian',     'P1000021', '2030-02-02', '+919880021212', 'prakash.rao@example.com',      'Jayanagar, Bengaluru'),
('Kavya',    'Shetty',       '1999-07-07', 'Female', 'Indian',     'P1000022', '2032-08-08', '+919820022222', 'kavya.shetty@example.com',     'Powai, Mumbai'),
('Imran',    'Sheikh',       '1986-04-04', 'Male',   'Indian',     'P1000023', '2031-11-11', '+919848023232', 'imran.sheikh@example.com',     'Gachibowli, Hyderabad'),
('Deepa',    'Pillai',       '1992-05-19', 'Female', 'Indian',     'P1000024', '2030-10-20', '+919847024242', 'deepa.pillai@example.com',     'Edappally, Kochi'),
('Tarun',    'Bose',         '1981-09-16', 'Male',   'Indian',     'P1000025', '2029-08-28', '+919830025252', 'tarun.bose@example.com',       'Park Street, Kolkata'),
('Ritu',     'Malhotra',     '1993-11-27', 'Female', 'Indian',     'P1000026', '2032-03-21', '+919810026262', 'ritu.malhotra@example.com',    'Vasant Kunj, Delhi'),
('Naveen',   'Chandra',      '1988-01-13', 'Male',   'Indian',     'P1000027', '2031-04-16', '+919840027272', 'naveen.chandra@example.com',   'Porur, Chennai'),
('Swati',    'Joshi',        '1995-08-24', 'Female', 'Indian',     'P1000028', '2033-05-25', '+919820028282', 'swati.joshi@example.com',      'Thane, Mumbai'),
('Wei',      'Chen',         '1985-12-12', 'Male',   'Singaporean','S4000029', '2031-12-01', '+6591000029',   'wei.chen@example.com',         'Orchard Road, Singapore'),
('Olivia',   'Brown',        '1990-06-30', 'Female', 'British',    'B2000030', '2032-09-09', '+447700030303', 'olivia.brown@example.com',     'Kensington, London');

-- ---------------------------------------------------------------------
-- FLIGHTS (ids 1-20). Gate always belongs to the source airport,
-- aircraft always belongs to the flight's airline.
-- ---------------------------------------------------------------------
INSERT INTO FLIGHT
 (flight_no, departure_date, departure_time, arrival_date, arrival_time, status,
  airline_id, aircraft_id, source_airport_id, destination_airport_id, gate_id)
VALUES
('AI101', '2026-10-10', '06:00:00', '2026-10-10', '08:45:00', 'Scheduled', 1, 1, 1, 2,  1),
('AI102', '2026-10-10', '10:00:00', '2026-10-10', '12:45:00', 'Scheduled', 1, 2, 2, 1,  4),
('6E201', '2026-10-10', '07:30:00', '2026-10-10', '08:45:00', 'Scheduled', 2, 3, 1, 4,  2),
('6E202', '2026-10-10', '18:00:00', '2026-10-10', '19:15:00', 'Scheduled', 2, 3, 4, 1, 10),
('6E305', '2026-10-11', '09:00:00', '2026-10-11', '11:10:00', 'Scheduled', 2, 4, 3, 2,  7),
('SG401', '2026-10-11', '14:00:00', '2026-10-11', '15:25:00', 'Scheduled', 3, 5, 5, 3, 13),
('EK501', '2026-10-12', '02:30:00', '2026-10-12', '04:45:00', 'Scheduled', 4, 6, 3, 7,  8),
('EK502', '2026-10-12', '22:00:00', '2026-10-13', '03:30:00', 'Scheduled', 4, 6, 7, 8, 19),
('SQ601', '2026-10-13', '09:00:00', '2026-10-13', '15:30:00', 'Scheduled', 5, 7, 1, 8,  3),
('SQ602', '2026-10-14', '16:00:00', '2026-10-14', '19:00:00', 'Scheduled', 5, 7, 8, 1, 22),
('AI111', '2026-10-15', '05:30:00', '2026-10-15', '07:45:00', 'Scheduled', 1, 8, 2, 3,  5),
('AI112', '2026-10-15', '20:00:00', '2026-10-15', '22:15:00', 'Scheduled', 1, 8, 3, 2,  9),
('6E411', '2026-10-16', '11:00:00', '2026-10-16', '12:10:00', 'Scheduled', 2, 4, 4, 5, 11),
('SG412', '2026-10-16', '15:00:00', '2026-10-16', '17:20:00', 'Scheduled', 3, 5, 6, 2, 16),
('AI121', '2026-10-17', '08:00:00', '2026-10-17', '10:30:00', 'Scheduled', 1, 1, 1, 6,  1),
('EK511', '2026-10-18', '03:00:00', '2026-10-18', '07:30:00', 'Scheduled', 4, 6, 7, 9, 20),
('AI131', '2026-10-20', '02:30:00', '2026-10-20', '08:00:00', 'Scheduled', 1, 2, 2, 10, 6),
('AI099', '2026-09-28', '06:00:00', '2026-09-28', '08:45:00', 'Arrived',   1, 1, 1, 2,  1),
('6E210', '2026-10-10', '12:00:00', '2026-10-10', '13:15:00', 'Delayed',   2, 4, 1, 4,  3),
('SG420', '2026-10-12', '09:00:00', '2026-10-12', '10:00:00', 'Cancelled', 3, 5, 5, 1, 14);

-- Past flight: actual times; delayed flight: delay minutes
UPDATE FLIGHT SET actual_departure = '2026-09-28 06:12:00',
                  actual_arrival   = '2026-09-28 08:50:00',
                  delay_minutes    = 12
WHERE flight_no = 'AI099';
UPDATE FLIGHT SET delay_minutes = 45 WHERE flight_no = '6E210';

-- ---------------------------------------------------------------------
-- FLIGHT_FARE: Economy + Business for every flight
-- (international = any airport id >= 7)
-- ---------------------------------------------------------------------
INSERT INTO FLIGHT_FARE (flight_id, `class`, base_price, seats_available)
SELECT flight_id, 'Economy', eco, 102
FROM (SELECT flight_id,
             CASE WHEN source_airport_id >= 7 OR destination_airport_id >= 7
                  THEN 18000 + flight_id * 250
                  ELSE 3500 + flight_id * 200 END AS eco
      FROM FLIGHT) x
UNION ALL
SELECT flight_id, 'Business', ROUND(eco * 2.8, 2), 18
FROM (SELECT flight_id,
             CASE WHEN source_airport_id >= 7 OR destination_airport_id >= 7
                  THEN 18000 + flight_id * 250
                  ELSE 3500 + flight_id * 200 END AS eco
      FROM FLIGHT) y;

-- ---------------------------------------------------------------------
-- FLIGHT_CREW: every crew member of the airline is assigned to its flights
-- ---------------------------------------------------------------------
INSERT INTO FLIGHT_CREW (flight_id, crew_id)
SELECT f.flight_id, c.crew_id
FROM FLIGHT f
JOIN CREW c ON c.airline_id = f.airline_id;

-- ---------------------------------------------------------------------
-- BOOKINGS (staged in a temp table, then resolved to seat ids / fares)
-- uid: 2 = staff1, 3 = agent1
-- ---------------------------------------------------------------------
CREATE TEMPORARY TABLE tmp_booking (
    ref VARCHAR(10), pid INT, fid INT, seat_no VARCHAR(5), status VARCHAR(12), uid INT
);

INSERT INTO tmp_booking VALUES
('PNR000001',  1,  1, '1A',  'Confirmed', 2),
('PNR000002',  2,  1, '5C',  'Confirmed', 2),
('PNR000003',  3,  1, '5D',  'Confirmed', 3),
('PNR000004',  4,  2, '2B',  'Confirmed', 3),
('PNR000005',  5,  2, '8A',  'Confirmed', 2),
('PNR000006',  6,  3, '4A',  'Confirmed', 2),
('PNR000007',  7,  3, '4B',  'Confirmed', 3),
('PNR000008',  8,  5, '1A',  'Confirmed', 2),
('PNR000009',  9,  5, '10F', 'Confirmed', 3),
('PNR000010', 10,  7, '1A',  'Confirmed', 2),
('PNR000011', 11,  7, '1B',  'Confirmed', 2),
('PNR000012', 12,  7, '12C', 'Confirmed', 3),
('PNR000013', 13,  9, '2A',  'Confirmed', 3),
('PNR000014', 14,  9, '6A',  'Confirmed', 2),
('PNR000015', 15, 11, '7A',  'Confirmed', 2),
('PNR000016', 16, 11, '7B',  'Confirmed', 3),
('PNR000017', 17, 15, '3F',  'Confirmed', 2),
('PNR000018', 18, 17, '1C',  'Confirmed', 3),
('PNR000019', 19, 17, '1D',  'Confirmed', 3),
('PNR000020', 20, 18, '5A',  'Confirmed', 2),
('PNR000021', 21, 18, '5B',  'Confirmed', 2),
('PNR000022', 22, 18, '5C',  'Confirmed', 3),
('PNR000023', 23, 20, '4A',  'Cancelled', 2),   -- flight cancelled by airline
('PNR000024', 24, 19, '6C',  'Confirmed', 3),
('PNR000025', 25, 16, '3A',  'Confirmed', 2),
('PNR000026', 26,  4, '9A',  'Cancelled', 3),   -- cancelled by passenger
('PNR000027', 27,  6, '9A',  'Pending',   2);   -- not yet paid / no ticket

INSERT INTO BOOKING
 (booking_reference, booking_date, booking_status, total_amount,
  passenger_id, flight_id, seat_id, booked_by)
SELECT t.ref,
       TIMESTAMP(DATE_SUB(f.departure_date, INTERVAL 7 DAY), '10:30:00'),
       t.status,
       ff.base_price,
       t.pid,
       t.fid,
       IF(t.status = 'Cancelled', NULL, s.seat_id),   -- cancelled bookings free the seat
       t.uid
FROM tmp_booking t
JOIN FLIGHT f       ON f.flight_id = t.fid
JOIN SEAT s         ON s.aircraft_id = f.aircraft_id AND s.seat_no = t.seat_no
JOIN FLIGHT_FARE ff ON ff.flight_id = t.fid AND ff.`class` = s.`class`
ORDER BY t.ref;

DROP TEMPORARY TABLE tmp_booking;

-- Keep fare seat counters in sync with seeded bookings
UPDATE FLIGHT_FARE ff
SET seats_available = seats_available - (
    SELECT COUNT(*)
    FROM BOOKING b
    JOIN SEAT s ON s.seat_id = b.seat_id
    WHERE b.flight_id = ff.flight_id
      AND s.`class` = ff.`class`
      AND b.booking_status <> 'Cancelled');

-- ---------------------------------------------------------------------
-- TICKETS: every Confirmed or Cancelled booking (Pending has none)
-- ---------------------------------------------------------------------
INSERT INTO TICKET (ticket_no, issue_date, fare_amount, status, booking_id)
SELECT CONCAT('TKT', LPAD(booking_id, 8, '0')),
       booking_date,
       total_amount,
       IF(booking_status = 'Cancelled', 'Cancelled', 'Issued'),
       booking_id
FROM BOOKING
WHERE booking_status IN ('Confirmed', 'Cancelled');

-- ---------------------------------------------------------------------
-- PAYMENTS: one per ticket (refunded if the ticket is cancelled)
-- ---------------------------------------------------------------------
INSERT INTO PAYMENT (payment_date, amount, currency, payment_mode, transaction_id, status, ticket_id)
SELECT issue_date,
       fare_amount,
       'INR',
       ELT(1 + MOD(ticket_id, 4), 'Card', 'UPI', 'NetBanking', 'Cash'),
       CONCAT('TXN', LPAD(ticket_id, 10, '0')),
       IF(status = 'Cancelled', 'Refunded', 'Success'),
       ticket_id
FROM TICKET;

-- ---------------------------------------------------------------------
-- CANCELLATIONS
-- ---------------------------------------------------------------------
INSERT INTO CANCELLATION (booking_id, cancel_date, reason, refund_amount, processed_by)
SELECT b.booking_id,
       TIMESTAMP(DATE_SUB(f.departure_date, INTERVAL 3 DAY), '14:00:00'),
       IF(f.status = 'Cancelled', 'Flight cancelled by airline', 'Cancelled by passenger'),
       IF(f.status = 'Cancelled', b.total_amount, ROUND(b.total_amount * 0.8, 2)),
       2
FROM BOOKING b
JOIN FLIGHT f ON f.flight_id = b.flight_id
WHERE b.booking_status = 'Cancelled';

-- ---------------------------------------------------------------------
-- BAGGAGE: checked bag for odd-numbered bookings, cabin bag for some others
-- ---------------------------------------------------------------------
INSERT INTO BAGGAGE (baggage_tag, baggage_type, weight, dimensions, fee, status, booking_id)
SELECT CONCAT('BG', LPAD(b.booking_id, 6, '0')),
       'Checked',
       10 + MOD(b.booking_id * 7, 18),
       '70x45x28',
       IF(10 + MOD(b.booking_id * 7, 18) > 15, (10 + MOD(b.booking_id * 7, 18) - 15) * 100, 0),
       IF(f.status = 'Arrived', 'Arrived', 'Checked-In'),
       b.booking_id
FROM BOOKING b
JOIN FLIGHT f ON f.flight_id = b.flight_id
WHERE b.booking_status = 'Confirmed' AND MOD(b.booking_id, 2) = 1;

INSERT INTO BAGGAGE (baggage_tag, baggage_type, weight, dimensions, fee, status, booking_id)
SELECT CONCAT('BC', LPAD(b.booking_id, 6, '0')),
       'Cabin', 6, '55x35x20', 0,
       IF(f.status = 'Arrived', 'Arrived', 'Checked-In'),
       b.booking_id
FROM BOOKING b
JOIN FLIGHT f ON f.flight_id = b.flight_id
WHERE b.booking_status = 'Confirmed' AND MOD(b.booking_id, 4) = 1;

-- ---------------------------------------------------------------------
-- CHECK-IN: only the past (arrived) flight AI099 has boarded passengers
-- ---------------------------------------------------------------------
INSERT INTO CHECK_IN (ticket_id, check_in_time, boarding_time, boarding_status)
SELECT t.ticket_id,
       TIMESTAMP(f.departure_date, SUBTIME(f.departure_time, '02:00:00')),
       TIMESTAMP(f.departure_date, SUBTIME(f.departure_time, '00:30:00')),
       'Boarded'
FROM TICKET t
JOIN BOOKING b ON b.booking_id = t.booking_id
JOIN FLIGHT f  ON f.flight_id = b.flight_id
WHERE f.flight_no = 'AI099' AND t.status = 'Issued';

SET SQL_SAFE_UPDATES = 1;

-- ---------------------------------------------------------------------
-- VERIFY: row counts per table
-- ---------------------------------------------------------------------
SELECT 'USER_ACCOUNT' AS tbl, COUNT(*) AS row_count FROM USER_ACCOUNT
UNION ALL SELECT 'AIRLINE',      COUNT(*) FROM AIRLINE
UNION ALL SELECT 'AIRPORT',      COUNT(*) FROM AIRPORT
UNION ALL SELECT 'GATE',         COUNT(*) FROM GATE
UNION ALL SELECT 'AIRCRAFT',     COUNT(*) FROM AIRCRAFT
UNION ALL SELECT 'SEAT',         COUNT(*) FROM SEAT
UNION ALL SELECT 'CREW',         COUNT(*) FROM CREW
UNION ALL SELECT 'PASSENGER',    COUNT(*) FROM PASSENGER
UNION ALL SELECT 'FLIGHT',       COUNT(*) FROM FLIGHT
UNION ALL SELECT 'FLIGHT_FARE',  COUNT(*) FROM FLIGHT_FARE
UNION ALL SELECT 'FLIGHT_CREW',  COUNT(*) FROM FLIGHT_CREW
UNION ALL SELECT 'BOOKING',      COUNT(*) FROM BOOKING
UNION ALL SELECT 'TICKET',       COUNT(*) FROM TICKET
UNION ALL SELECT 'PAYMENT',      COUNT(*) FROM PAYMENT
UNION ALL SELECT 'BAGGAGE',      COUNT(*) FROM BAGGAGE
UNION ALL SELECT 'CHECK_IN',     COUNT(*) FROM CHECK_IN
UNION ALL SELECT 'CANCELLATION', COUNT(*) FROM CANCELLATION;
