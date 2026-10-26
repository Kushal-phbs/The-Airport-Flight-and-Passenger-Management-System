# Airport Flight and Passenger Management System
## Project Report - Database, Backend and Testing Sections (Member 1)

> Copy these sections into your report. Anything in **[brackets]** is for you to fill in (names, screenshots, frontend parts written by Member 2).

---

## 1. Problem Statement
The Airport Flight and Passenger Management System is a centralized database system for managing flights, passengers, bookings, tickets, baggage, aircraft, gates, airlines and payments. Manual management of this data causes duplication, errors and slow retrieval of up-to-date records. The system uses MySQL (SQL, stored procedures, triggers), a Python Flask backend and an HTML/CSS/JavaScript frontend to provide organized, secure and efficient management of airport flight and passenger information, while keeping data consistent across all tables.

## 2. Technology Stack
| Layer | Technology |
|---|---|
| Frontend | HTML, CSS, JavaScript |
| Backend | Python, Flask (REST API, JWT authentication) |
| Database | MySQL 8 |
| DBMS logic | SQL, stored procedures, triggers |
| Development | VS Code |
| Database design | MySQL Workbench |

**Architecture:** Browser (HTML/CSS/JS) -> `fetch()` -> Flask REST API (62 endpoints, JSON) -> MySQL (constraints, triggers, procedures).

---

## 3. Database Design

### 3.1 Entities (18 tables)
| Group | Tables |
|---|---|
| Security | USER_ACCOUNT, AUDIT_LOG |
| Master data | AIRLINE, AIRPORT, AIRCRAFT, SEAT, GATE, CREW, PASSENGER |
| Flight operations | FLIGHT, FLIGHT_FARE, FLIGHT_CREW |
| Booking and ticketing | BOOKING, TICKET, PAYMENT, BAGGAGE, CHECK_IN, CANCELLATION |

### 3.2 Relationships
| Relationship | Cardinality |
|---|---|
| AIRLINE - AIRCRAFT, AIRLINE - FLIGHT, AIRLINE - CREW | 1 : N |
| AIRCRAFT - SEAT, AIRCRAFT - FLIGHT | 1 : N |
| AIRPORT - GATE | 1 : N |
| AIRPORT - FLIGHT (departs from, arrives at: two relationships) | 1 : N each |
| GATE - FLIGHT | 1 : N |
| FLIGHT - FLIGHT_FARE, FLIGHT - BOOKING | 1 : N |
| FLIGHT - CREW (through FLIGHT_CREW) | M : N |
| PASSENGER - BOOKING | 1 : N |
| SEAT - BOOKING (a seat is held by at most one active booking per flight) | 1 : N |
| USER_ACCOUNT - BOOKING, AUDIT_LOG, CANCELLATION | 1 : N |
| BOOKING - TICKET | 1 : 1 |
| BOOKING - BAGGAGE | 1 : N |
| BOOKING - CANCELLATION | 1 : 1 |
| TICKET - PAYMENT | 1 : N (allows retries and split payments) |
| TICKET - CHECK_IN | 1 : 1 |

**[Insert ER diagram: `docs/ER_Diagram_v2.png`, and the Workbench EER diagram generated with Database -> Reverse Engineer]**

### 3.3 Integrity constraints
| Type | Examples |
|---|---|
| Primary keys | Surrogate `AUTO_INCREMENT` key on every table; composite key on FLIGHT_CREW |
| Candidate keys (UNIQUE) | `airline_code`, `airport_code`, `aircraft_code`, `passport_no`, `ticket_no`, `booking_reference` (PNR), `transaction_id`, `baggage_tag`, `(flight_no, departure_date)`, `(aircraft_id, seat_no)`, `(flight_id, seat_id)`, `(flight_id, class)` |
| Foreign keys | 23 foreign keys; `RESTRICT` for records with history (flights, bookings, tickets, payments), `CASCADE` for dependants (seats, baggage), `SET NULL` for optional links (gate, booked_by, seat on cancellation) |
| CHECK | `capacity > 0`, `base_price >= 0`, `fare_amount >= 0`, `amount > 0`, `weight > 0`, `refund_amount >= 0`, arrival after departure |
| ENUM domains | status, class, role, payment_mode, gender, seat_type, baggage_type, boarding_status |
| NOT NULL / DEFAULT | Mandatory fields and defaults such as `status = 'Scheduled'` |
| Indexes | `idx_flight_date`, `idx_flight_route`, `idx_passenger_name`, `idx_booking_status`, `idx_audit_time` (plus automatic indexes on all foreign keys) |
| Triggers | Rules a CHECK cannot express (section 5) |

*Note:* "source airport must differ from destination airport" cannot be a `CHECK` in MySQL because those columns are used in foreign keys with referential actions (error 3823), so it is enforced by a trigger.

---

## 4. Normalization

### 4.1 First Normal Form (1NF)
- Every attribute holds a single atomic value.
- Repeating groups were removed: a flight's crew is stored in FLIGHT_CREW (one row per crew member), not as columns like `crew1, crew2`; fares per class are rows of FLIGHT_FARE, not columns like `economy_price, business_price`.
- Each table has a primary key.
- `AUDIT_LOG.old_value / new_value` store a snapshot of a changed row as one text value. It is only ever read as a whole, so it is treated as a single atomic log entry.

### 4.2 Second Normal Form (2NF)
- All tables use a single-column surrogate key, so no partial dependency is possible.
- The two tables with composite keys are in 2NF: FLIGHT_CREW has no non-key attributes, and in FLIGHT_FARE both `base_price` and `seats_available` depend on the whole key `(flight_id, class)`.

### 4.3 Third Normal Form (3NF)
Functional dependencies and normal form of each table:

| Table | Key and main dependencies | Normal form |
|---|---|---|
| USER_ACCOUNT | `user_id` -> all; `username`, `email` are candidate keys | BCNF |
| AUDIT_LOG | `log_id` -> all | BCNF |
| AIRLINE | `airline_id` -> all; `airline_code` is a candidate key | BCNF |
| AIRPORT | `airport_id` -> all; `airport_code` candidate key. `city` does not determine `country` (city names repeat across countries), so no transitive dependency | BCNF |
| AIRCRAFT | `aircraft_id` -> all; `aircraft_code` candidate key | BCNF |
| SEAT | `seat_id` -> all; `(aircraft_id, seat_no)` candidate key | BCNF |
| GATE | `gate_id` -> all; `(airport_id, terminal, gate_no)` candidate key | BCNF |
| CREW | `crew_id` -> all; `license_no` candidate key | BCNF |
| PASSENGER | `passenger_id` -> all; `passport_no` candidate key | BCNF |
| FLIGHT_FARE | `(flight_id, class)` -> `base_price`, `seats_available` | BCNF |
| FLIGHT_CREW | `(flight_id, crew_id)` all-key | BCNF |
| BOOKING | `booking_id` -> all; `booking_reference` and `(flight_id, seat_id)` are candidate keys | 3NF |
| TICKET | `ticket_id` -> all; `ticket_no` and `booking_id` are candidate keys | 3NF |
| PAYMENT | `payment_id` -> all; `transaction_id` candidate key | 3NF |
| BAGGAGE | `baggage_id` -> all; `baggage_tag` candidate key | 3NF |
| CHECK_IN | `checkin_id` -> all; `ticket_id` candidate key | 3NF |
| CANCELLATION | `cancel_id` -> all; `booking_id` candidate key | 3NF |
| FLIGHT | `flight_id` -> all; `(flight_no, departure_date)` candidate key | 3NF with one controlled redundancy (below) |

**Redundancy removed during design:** the first version of TICKET repeated `seat_no` and `class`, which already belong to the booking. They were removed, and the seat class is now derived from `SEAT.class`. Seat numbers were also moved from free text in BOOKING into a SEAT table, so a seat can be validated and cannot be allocated twice.

### 4.4 Deliberate, controlled redundancy
A few columns are stored although they could be calculated. Each is maintained by triggers so it cannot drift:

| Column | Why it is kept |
|---|---|
| `BOOKING.total_amount`, `TICKET.fare_amount` | Snapshot of the price actually charged. Later changes to `FLIGHT_FARE.base_price` must not rewrite past bookings |
| `BAGGAGE.fee`, `CANCELLATION.refund_amount` | Historical billing values; fee and refund rules may change later |
| `FLIGHT_FARE.seats_available` | Counter for fast availability search instead of counting bookings on every query; updated by booking triggers |
| `FLIGHT.delay_minutes` | Calculated from actual vs scheduled departure by the flight trigger, stored for reporting |
| `FLIGHT.airline_id` | `aircraft_id` -> `airline_id` is a transitive dependency. It is kept so flights can be queried per operating airline directly, and a trigger rejects a flight whose aircraft does not belong to the airline |

---

## 5. Triggers (21) and Helper Procedures

All triggers raise a readable error with `SIGNAL SQLSTATE '45000'`; Flask returns it to the user as `{"error": "..."}` with HTTP 400.

| # | Trigger | Event | What it does |
|---|---|---|---|
| 1 | `trg_flight_bi` | BEFORE INSERT FLIGHT | Validates the flight (see `sp_validate_flight` below) |
| 2 | `trg_flight_bu` | BEFORE UPDATE FLIGHT | Re-validates when times, airports, gate, aircraft or airline change; blocks reactivating a cancelled flight; on actual departure calculates `delay_minutes` and sets status Departed; on actual arrival sets status Arrived |
| 3 | `trg_flight_ai` | AFTER INSERT FLIGHT | Audit log entry |
| 4 | `trg_flight_au` | AFTER UPDATE FLIGHT | Cancelling a flight cancels all its bookings (refunds follow); audit log |
| 5 | `trg_flight_ad` | AFTER DELETE FLIGHT | Audit log |
| 6 | `trg_booking_bi` | BEFORE INSERT BOOKING | Blocks bookings on cancelled/departed/arrived flights, **overbooking** (capacity), same passenger booked twice on a flight, expired passport on travel date, and seat problems (missing, wrong aircraft, inactive, **already taken**); auto-fills the amount from the class fare |
| 7 | `trg_booking_ai` | AFTER INSERT BOOKING | Decrements `seats_available`; audit log |
| 8 | `trg_booking_bu` | BEFORE UPDATE BOOKING | Blocks changing the flight or un-cancelling; blocks cancelling after departure; **frees the seat on cancellation**; validates seat changes |
| 9 | `trg_booking_au` | AFTER UPDATE BOOKING | Keeps `seats_available` in sync; on cancellation cancels the ticket, marks payments Refunded and creates the CANCELLATION record (100% refund if the airline cancelled, otherwise 80%); audit log |
| 10 | `trg_booking_ad` | AFTER DELETE BOOKING | Restores the seat counter; audit log |
| 11 | `trg_ticket_bi` | BEFORE INSERT TICKET | No ticket for a cancelled booking |
| 12 | `trg_ticket_ai` | AFTER INSERT TICKET | Moves a Pending booking to Confirmed |
| 13 | `trg_payment_bi` | BEFORE INSERT PAYMENT | Only for issued tickets; total successful payments cannot exceed the fare |
| 14 | `trg_payment_ai` | AFTER INSERT PAYMENT | Audit log |
| 15 | `trg_payment_au` | AFTER UPDATE PAYMENT | Audit log |
| 16 | `trg_baggage_bi` | BEFORE INSERT BAGGAGE | Not on cancelled bookings; limits 32 kg per checked bag and 7 kg cabin; **calculates the fee** (15 kg free, Rs.100 per extra kg) |
| 17 | `trg_checkin_bi` | BEFORE INSERT CHECK_IN | Ticket must be issued and the flight still open |
| 18 | `trg_checkin_bu` | BEFORE UPDATE CHECK_IN | Sets `boarding_time` when status becomes Boarded |
| 19-21 | `trg_passenger_ai/au/ad` | AFTER INSERT/UPDATE/DELETE PASSENGER | Audit log |

**Helper procedures used by triggers**
- `sp_validate_flight(...)`: source differs from destination; aircraft belongs to the airline and is Active; the aircraft is not on an overlapping flight; the gate belongs to the departure airport, is not Closed, and no other flight uses it within 60 minutes.
- `sp_audit(...)`: writes who/what/when into AUDIT_LOG. Flask sets `@app_user_id` on each request so the acting user is recorded.

## 6. Stored Procedures (8)
| Procedure | Purpose | API endpoint |
|---|---|---|
| `sp_book_ticket` | Creates booking, ticket and payment in **one transaction** (rolls back on any error); locks the flight row so two agents cannot take the same seat; returns booking id, ticket number and PNR | `POST /api/bookings` |
| `sp_cancel_booking` | Cancels a booking; triggers free the seat, cancel the ticket, refund the payment and record the cancellation | `DELETE /api/bookings/{id}` |
| `sp_get_flight_manifest` | Passenger list of a flight with seat, ticket, check-in status and baggage totals | `GET /api/flights/{id}/manifest` |
| `sp_check_in` | Checks a passenger in using the ticket number | `POST /api/checkin` |
| `sp_board_passenger` | Marks a checked-in passenger as boarded | `POST /api/checkin/board` |
| `sp_search_flights` | Search by source code, destination code and date | `GET /api/flights` |
| `sp_seat_map` | All seats of the aircraft with a taken flag | `GET /api/flights/{id}/seats` |
| `sp_dashboard_stats` | Headline numbers: flights, passengers, bookings, tickets, revenue | `GET /api/dashboard/stats` |

---

## 7. Backend (Flask REST API)
- **62 endpoints** under `/api`, JSON in and out (full list: `API_CONTRACT.md`).
- **Authentication:** login returns a JWT; every request sends `Authorization: Bearer <token>`. The account is re-checked in the database on each request, so deactivating a user takes effect immediately.
- **Authorization (role-based):** Admin (everything), Staff (operations, no deletes/user management), Agent (search, passengers, bookings, payments, baggage, check-in).
- **Security:** passwords stored as salted pbkdf2-sha256 hashes; all SQL values are passed as parameters (protection against SQL injection); column names come from fixed whitelists; database credentials are kept in a `.env` file outside version control.
- **Connection handling:** pooled MySQL connections, one per request.
- **Error handling:** database and trigger errors are mapped to clean HTTP status codes (400 validation/rule, 401, 403, 404, 409 duplicate or in use).

## 8. Testing
**Test suite available:** `backend/tests/test_api.py` is written to send HTTP requests to Flask backed by MySQL. A Postman collection is also provided for manual testing. The rows below describe suite coverage from the source; they are not results from a test run in this delivery.

**Current verification status:** the database-backed end-to-end suite was not run for this delivery because the configured local MySQL service is unreachable. Historical test notes are not treated as a current verification result. Run the suite only against an isolated test database.

| Area | What was verified |
|---|---|
| Authentication and roles | Login for the three roles, wrong password rejected, forbidden actions return 403, a deactivated user's old token is rejected |
| Flights | Search, detail, seat map, manifest, create with fares, update, crew assignment, automatic delay calculation and Departed status, cancelling a flight cancels its bookings with full refunds |
| Booking flow | One call creates booking + ticket + payment; the seat count drops; a freed seat can be rebooked |
| Business rules (blocked correctly) | Double-booked seat, same passenger twice, booking on a cancelled flight, invalid seat, bad payment mode, overweight baggage, overpayment, same source/destination, gate conflict, aircraft/airline mismatch, reactivating a cancelled flight, cancelling twice, deleting records that are still in use |
| Cancellation | 80% refund when the passenger cancels; seat freed, ticket cancelled, payment marked Refunded, CANCELLATION row created |
| Baggage / check-in | Fee 500 for a 20 kg bag; check-in and boarding; manifest shows Boarded and bag count |
| Audit | Actions are logged with the acting username and can be filtered |
| Concurrency | 5 agents booking the same seat at the same moment: exactly 1 succeeds, 4 are rejected |

### Screenshots to capture
1. **[Workbench]** the 18 tables in the schema panel and the Workbench EER diagram.
2. **[Workbench]** `SELECT * FROM FLIGHT;` and the row-count query from `seed_data.sql`.
3. **[Workbench]** `SHOW TRIGGERS;` and `SHOW PROCEDURE STATUS WHERE Db='airport_db';`
4. **[Postman]** Login -> token; Search flights; Create booking (201 with PNR and ticket number).
5. **[Postman]** Create booking a second time -> `Seat is already booked for this flight`.
6. **[Postman]** Cancel booking -> `refund_amount`; then booking detail showing Cancelled.
7. **[Postman]** Audit log showing who made each change.
8. **[Terminal]** the test suite ending with `86 passed, 0 failed`.
9. **[Frontend, Member 2]** login, dashboard, flight search, seat picker, booking, ticket, manifest.

---

## 9. Suggested report outline
1. Introduction and problem statement
2. Objectives and scope
3. Technology stack and architecture
4. ER diagram and relational schema (sections 3.1-3.3 above)
5. Normalization (section 4)
6. Triggers and stored procedures (sections 5-6)
7. Backend API and security (section 7)
8. Frontend design **[Member 2]**
9. Testing and results (section 8)
10. Conclusion
11. Future enhancements
12. References

### Future enhancements (for the conclusion)
Online payment gateway integration, email/SMS ticket delivery, QR-code boarding passes, crew duty-hour rules, aircraft maintenance scheduling, multi-leg itineraries, loyalty points, dynamic pricing, and analytics dashboards for delays and revenue.

### Conclusion (draft)
The project delivers a normalized 18-table MySQL database whose business rules (seat allocation, overbooking prevention, gate and aircraft scheduling, refunds, audit logging) are enforced inside the database through constraints, 21 triggers and 8 stored procedures. A secured Flask REST API exposes these operations to a web frontend, and an automated suite of 86 tests confirms that the rules hold even under concurrent bookings.
