# ER diagram and entity guide

The visual model is [ER_Diagram_v2.png](ER_Diagram_v2.png). `database/schema.sql` is authoritative for the implemented 18-table schema.

## Entities and relationships

- `AIRLINE(airline_id PK)`: one airline operates many aircraft, flights, and crew.
- `AIRPORT(airport_id PK)`: one airport has many gates and participates in many flights as departure or arrival.
- `AIRCRAFT(aircraft_id PK, airline_id FK)`: one airline owns/operates aircraft; aircraft has many seats and scheduled flights.
- `SEAT(seat_id PK, aircraft_id FK)`: unique seat number per aircraft, with class/type.
- `GATE(gate_id PK, airport_id FK)`: unique gate within an airport/terminal; can be assigned to flights over time.
- `CREW(crew_id PK, airline_id FK)`: airline crew assigned to flights through `FLIGHT_CREW` (many-to-many).
- `FLIGHT(flight_id PK)`: references airline, aircraft, departure airport, arrival airport, and optional gate. Flight number/date is unique.
- `FLIGHT_FARE(fare_id PK, flight_id FK)`: per-flight, per-class fare; `(flight_id,class)` is unique.
- `PASSENGER(passenger_id PK)`: passenger and travel-document details; passport number is unique.
- `BOOKING(booking_id PK, passenger_id FK, flight_id FK, seat_id FK nullable)`: reservations. One passenger/flight has many bookings; `(flight_id,seat_id)` prevents duplicate seat assignment. Cancellation nulls seat_id so the seat can be reused.
- `TICKET(ticket_id PK, booking_id FK unique)`: at most one ticket per booking.
- `PAYMENT(payment_id PK, ticket_id FK)`: a ticket can have multiple payment attempts.
- `BAGGAGE(baggage_id PK, booking_id FK)`: a booking has zero or more baggage records.
- `CHECK_IN(checkin_id PK, ticket_id FK unique)`: at most one check-in row per ticket.
- `CANCELLATION(cancel_id PK, booking_id FK unique)`: at most one cancellation record per booking.
- `USER_ACCOUNT(user_id PK)`: application user; users can make bookings and process cancellations.
- `AUDIT_LOG(log_id PK, user_id FK nullable)`: audit history attributed to an account where available.

## Cardinalities

```text
AIRLINE 1:N AIRCRAFT, FLIGHT, CREW       AIRPORT 1:N GATE
AIRPORT 1:N FLIGHT (departure / arrival) AIRCRAFT 1:N SEAT, FLIGHT
FLIGHT 1:N FLIGHT_FARE, BOOKING          PASSENGER 1:N BOOKING
FLIGHT N:M CREW via FLIGHT_CREW          BOOKING 1:0..1 TICKET
TICKET 1:N PAYMENT                       BOOKING 1:N BAGGAGE
TICKET 1:0..1 CHECK_IN                   BOOKING 1:0..1 CANCELLATION
```

`USER_ACCOUNT` relates one-to-many to bookings, cancellations, and audit entries. Optional gate, seat-after-cancel, booked-by, processed-by, and audit-user references can be NULL.
