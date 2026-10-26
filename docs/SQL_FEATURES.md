# SQL features and examples

Run the database files in this order against a dedicated MySQL 8.0.16+ development database:

1. `database/schema.sql` — **destructive**: drops and recreates `airport_db`, then creates the 18 InnoDB tables, keys, checks, and indexes.
2. `database/seed_data.sql` — sample master data, accounts, schedules, passengers, bookings, tickets, payments, baggage, and check-in rows.
3. `database/triggers.sql` — trigger helper routines and validation/audit/booking/payment/baggage/check-in triggers.
4. `database/procedures.sql` — search, dashboard, booking, cancellation, manifest, seat map, and check-in procedures.
5. `database/views.sql` — scheduled flight, occupancy, and successful payment reporting views.

Reporting views: `v_scheduled_flights` joins active schedules to airport, airline, and gate labels; `v_flight_occupancy` counts non-cancelled bookings against aircraft capacity; `v_successful_payment_revenue` aggregates successful payment amounts per ticket.

## Example SQL reports

```sql
-- Scheduled flights by departure time
SELECT f.flight_no, f.departure_date, f.departure_time,
       src.airport_code AS source, dst.airport_code AS destination,
       al.airline_name, f.status
FROM FLIGHT f
JOIN AIRPORT src ON src.airport_id = f.source_airport_id
JOIN AIRPORT dst ON dst.airport_id = f.destination_airport_id
JOIN AIRLINE al ON al.airline_id = f.airline_id
WHERE f.status IN ('Scheduled', 'Boarding', 'Delayed')
ORDER BY f.departure_date, f.departure_time;

-- Passenger booking history (including cancellations)
SELECT p.passport_no, CONCAT(p.first_name, ' ', COALESCE(p.last_name,'')) AS passenger,
       b.booking_reference, f.flight_no, b.booking_status, b.total_amount
FROM PASSENGER p
JOIN BOOKING b ON b.passenger_id = p.passenger_id
JOIN FLIGHT f ON f.flight_id = b.flight_id
WHERE p.passenger_id = ?
ORDER BY b.booking_date DESC;

-- Flight occupancy; HAVING keeps flights with at least one active booking
SELECT f.flight_no, f.departure_date, COUNT(b.booking_id) AS active_bookings,
       ac.capacity, ROUND(100 * COUNT(b.booking_id) / ac.capacity, 1) AS occupancy_pct
FROM FLIGHT f
JOIN AIRCRAFT ac ON ac.aircraft_id = f.aircraft_id
LEFT JOIN BOOKING b ON b.flight_id = f.flight_id AND b.booking_status <> 'Cancelled'
GROUP BY f.flight_id, f.flight_no, f.departure_date, ac.capacity
HAVING COUNT(b.booking_id) > 0
ORDER BY occupancy_pct DESC;

-- Revenue from successful payments
SELECT t.ticket_no, SUM(p.amount) AS paid_amount
FROM TICKET t
JOIN PAYMENT p ON p.ticket_id = t.ticket_id
WHERE p.status = 'Success'
GROUP BY t.ticket_id, t.ticket_no
ORDER BY paid_amount DESC;

-- Bookings with no baggage (LEFT JOIN)
SELECT b.booking_reference, f.flight_no
FROM BOOKING b
JOIN FLIGHT f ON f.flight_id = b.flight_id
LEFT JOIN BAGGAGE bg ON bg.booking_id = b.booking_id
WHERE b.booking_status = 'Confirmed'
GROUP BY b.booking_id, b.booking_reference, f.flight_no
HAVING COUNT(bg.baggage_id) = 0;

-- Correlated subquery: flights priced above the mean flight fare
SELECT ff.flight_id, ff.class, ff.base_price
FROM FLIGHT_FARE ff
WHERE ff.base_price > (SELECT AVG(base_price) FROM FLIGHT_FARE)
ORDER BY ff.base_price DESC;
```

## Stored procedures

- `sp_book_ticket(passenger, flight, seat, payment_mode, user, OUT booking, OUT ticket, OUT PNR)`: starts a transaction, locks the flight row, inserts booking/ticket/payment, and rolls back all writes on error.
- `sp_cancel_booking(booking, reason, user, OUT refund)`: marks the booking cancelled; triggers release the seat, cancel the ticket, refund successful payment records, and create a cancellation record.
- `sp_search_flights(source_code, destination_code, date)`: optional-filter flight search.
- `sp_seat_map(flight_id)`: seat list with taken flag.
- `sp_get_flight_manifest(flight_id)`: passenger, ticket, check-in, and baggage summary.
- `sp_check_in(ticket_no, user, OUT checkin_id)` and `sp_board_passenger(ticket_no, user)`: check-in and boarding workflow.
- `sp_dashboard_stats()`: aggregate dashboard counters and successful revenue.
- `sp_audit(...)` and `sp_validate_flight(...)` are helper routines called by triggers.

## Trigger groups

There are 21 triggers in `database/triggers.sql` (plus helper procedures). Flight triggers validate endpoints, schedule overlaps, operating airline/aircraft consistency, and gate allocation, and write audit events. Booking triggers validate passport/flight/seat/business rules, adjust fare seat counters, release seats on cancellation, propagate cancellations to tickets/payments, and record refunds. Ticket and payment triggers enforce payment lifecycle rules and audit changes. Baggage triggers enforce weight rules and calculate fees. Check-in triggers validate eligibility and record boarding time. Passenger triggers write audit events. The intent is to enforce rules even when a database write does not come through the browser.

## Transaction example

`sp_book_ticket` uses `START TRANSACTION`, locks the selected flight row with `SELECT ... FOR UPDATE`, and commits only after booking, ticket, and payment are all inserted. An exception handler runs `ROLLBACK` and re-raises the SQL error. Use this routine rather than inserting booking-related rows independently.


## Views

`sql
SELECT * FROM v_scheduled_flights ORDER BY departure_date, departure_time;
SELECT * FROM v_flight_occupancy WHERE occupancy_percent >= 75 ORDER BY occupancy_percent DESC;
SELECT * FROM v_successful_payment_revenue ORDER BY successful_amount DESC;
`
