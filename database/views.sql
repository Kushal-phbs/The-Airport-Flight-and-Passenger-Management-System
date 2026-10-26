-- =====================================================================
-- Airport Flight and Passenger Management System
-- views.sql -- run after schema.sql (may run after seed_data.sql for demo output)
-- Read-only reporting views; CREATE OR REPLACE makes this file repeatable.
-- =====================================================================
USE airport_db;

-- Scheduled operations joined to useful airport/operator labels.
CREATE OR REPLACE VIEW v_scheduled_flights AS
SELECT f.flight_id, f.flight_no, f.departure_date, f.departure_time,
       f.arrival_date, f.arrival_time, f.status, f.delay_minutes,
       al.airline_name, al.airline_code,
       src.airport_code AS source_code, src.city AS source_city,
       dst.airport_code AS destination_code, dst.city AS destination_city,
       g.terminal, g.gate_no
FROM FLIGHT f
JOIN AIRLINE al ON al.airline_id = f.airline_id
JOIN AIRPORT src ON src.airport_id = f.source_airport_id
JOIN AIRPORT dst ON dst.airport_id = f.destination_airport_id
LEFT JOIN GATE g ON g.gate_id = f.gate_id
WHERE f.status IN ('Scheduled', 'Boarding', 'Delayed');

-- Booking counts ignore cancelled rows while retaining flights with zero bookings.
CREATE OR REPLACE VIEW v_flight_occupancy AS
SELECT f.flight_id, f.flight_no, f.departure_date, ac.capacity,
       COUNT(b.booking_id) AS active_bookings,
       ac.capacity - COUNT(b.booking_id) AS seats_remaining,
       ROUND(100.0 * COUNT(b.booking_id) / NULLIF(ac.capacity, 0), 1) AS occupancy_percent
FROM FLIGHT f
JOIN AIRCRAFT ac ON ac.aircraft_id = f.aircraft_id
LEFT JOIN BOOKING b ON b.flight_id = f.flight_id AND b.booking_status <> 'Cancelled'
GROUP BY f.flight_id, f.flight_no, f.departure_date, ac.capacity;

-- Successful payment amounts are the revenue basis used by dashboard reporting.
CREATE OR REPLACE VIEW v_successful_payment_revenue AS
SELECT t.ticket_id, t.ticket_no, b.booking_reference, f.flight_no,
       SUM(p.amount) AS successful_amount,
       MAX(p.currency) AS currency
FROM TICKET t
JOIN BOOKING b ON b.booking_id = t.booking_id
JOIN FLIGHT f ON f.flight_id = b.flight_id
JOIN PAYMENT p ON p.ticket_id = t.ticket_id AND p.status = 'Success'
GROUP BY t.ticket_id, t.ticket_no, b.booking_reference, f.flight_no;

SHOW FULL TABLES WHERE Table_type = 'VIEW';
