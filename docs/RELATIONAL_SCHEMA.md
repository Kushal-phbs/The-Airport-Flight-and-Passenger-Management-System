# Relational schema and normalization

This summarizes the 18 relations created by `database/schema.sql`; PK, FK, and UQ mean primary key, foreign key, and unique constraint. The SQL file is authoritative.

```text
USER_ACCOUNT(user_id PK, username UQ, password_hash, role, email UQ, is_active, created_at, last_login)
AUDIT_LOG(log_id PK, user_id FK nullable, action, table_name, record_id, old_value, new_value, log_time)
AIRLINE(airline_id PK, airline_name, airline_code UQ, country, contact_no, email, is_active)
AIRPORT(airport_id PK, airport_name, city, country, airport_code UQ, timezone)
AIRCRAFT(aircraft_id PK, aircraft_code UQ, model, manufacturer, year, capacity, status, airline_id FK)
SEAT(seat_id PK, aircraft_id FK, seat_no, class, seat_type, is_active; UQ aircraft_id+seat_no)
GATE(gate_id PK, gate_no, terminal, status, airport_id FK; UQ airport_id+terminal+gate_no)
CREW(crew_id PK, first_name, last_name, role, license_no UQ, phone_no, airline_id FK)
PASSENGER(passenger_id PK, names, dob, gender, nationality, passport_no UQ, expiry, phone, email, address)
FLIGHT(flight_id PK, flight_no, departure date/time, arrival date/time, actual times, delay, status, airline_id FK, aircraft_id FK, source_airport_id FK, destination_airport_id FK, gate_id FK nullable; UQ flight_no+departure_date)
FLIGHT_FARE(fare_id PK, flight_id FK, class, base_price, seats_available; UQ flight_id+class)
FLIGHT_CREW(flight_id PK/FK, crew_id PK/FK)
BOOKING(booking_id PK, booking_reference UQ, booking_date, booking_status, total_amount, passenger_id FK, flight_id FK, seat_id FK nullable, booked_by FK nullable; UQ flight_id+seat_id)
TICKET(ticket_id PK, ticket_no UQ, issue_date, fare_amount, status, booking_id FK UQ)
PAYMENT(payment_id PK, payment_date, amount, currency, payment_mode, transaction_id UQ, status, ticket_id FK)
BAGGAGE(baggage_id PK, baggage_tag UQ, baggage_type, weight, dimensions, fee, status, booking_id FK)
CHECK_IN(checkin_id PK, ticket_id FK UQ, check_in_time, boarding_time, boarding_status)
CANCELLATION(cancel_id PK, booking_id FK UQ, cancel_date, reason, refund_amount, processed_by FK nullable)
```

## Constraints and indexes

The schema uses non-null, default, unique, enum, and check constraints for required values and domains. Checks include positive aircraft capacity and baggage weight, nonnegative fares/refunds, positive payment amounts, and arrival later than scheduled departure. Foreign keys preserve referential integrity. Explicit indexes support flight date/route, passenger name, booking status, and audit time; InnoDB also indexes FK columns as required.

Cross-row flight and booking rules are implemented in triggers/procedures: airport endpoints differ, aircraft and airline agree, schedules do not overlap, gates are valid, and seats are available. The `(flight_id,seat_id)` unique key blocks duplicate seats; cancelled bookings clear the nullable seat reference, permitting reuse while retaining history.

## Normalization

The relations avoid repeating groups and keep airline, airport, aircraft, passenger, and crew facts in their own tables. `FLIGHT_CREW` resolves a many-to-many relation and `FLIGHT_FARE` stores class fares as rows. Non-key columns describe their relation's key, supporting 3NF. Some trigger-maintained snapshots/counters (`total_amount`, `fare_amount`, `seats_available`, `delay_minutes`, baggage fee, refund) retain historical billing values or support fast reporting. `FLIGHT.airline_id` explicitly stores the operator and trigger validation ensures agreement with the aircraft's airline.
