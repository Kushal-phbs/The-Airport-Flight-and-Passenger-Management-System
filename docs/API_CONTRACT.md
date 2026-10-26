# API Contract (Frontend <-> Flask)

Base URL: `http://localhost:5000/api`   All bodies are JSON.

## Authentication
`POST /login` -> `{ "token": "...", "user": {"user_id":1,"username":"admin","role":"Admin"} }`
Send the token on **every other request**: `Authorization: Bearer <token>`.
Token lasts 8 hours; a `401` means "log in again".

## Errors (always the same shape)
```json
{ "error": "Seat is already booked for this flight" }
```
| Status | Meaning |
|---|---|
| 400 | Bad input or a business rule blocked it (trigger message) - **show `error` to the user** |
| 401 | Not logged in / token expired |
| 403 | Role not allowed |
| 404 | Not found |
| 409 | Duplicate value, or record still in use |
| 500 | Server/database problem |

## Roles
- **Admin**: everything. **Staff**: everything except deletes, user management, audit log and airline/airport edits.
- **Agent**: search, passengers, bookings, payments, baggage, check-in (no flight/aircraft/gate editing).

## Formats
Dates `YYYY-MM-DD`, times `HH:MM:SS`, datetimes `YYYY-MM-DD HH:MM:SS`, money as numbers.

---

## Account / dashboard
| Method | Endpoint | Roles | Notes |
|---|---|---|---|
| GET | /health | public | `{status, database}` |
| POST | /login | public | body `{username, password}` |
| GET | /me | any | current user |
| GET | /dashboard/stats | any | `total_flights, upcoming_flights, delayed_flights, cancelled_flights, total_passengers, active_bookings, cancelled_bookings, tickets_issued, total_revenue` |
| GET | /users | Admin | |
| POST | /users | Admin | `{username, password, role, email?}` |
| PUT | /users/{id} | Admin | any of `role, email, is_active, password` |
| GET | /audit | Admin | `?table_name=&user_id=&action=&limit=` |

## Flights
| Method | Endpoint | Roles | Notes |
|---|---|---|---|
| GET | /flights?from=MAA&to=DEL&date=2026-10-10 | any | all filters optional (airport codes). Returns `flight_id, flight_no, airline_name, source, destination, departure_date/time, arrival_date/time, status, delay_minutes, terminal, gate_no, economy_fare, economy_seats, business_fare, business_seats` |
| GET | /flights/{id} | any | full detail + `fares[]` + `crew[]` |
| POST | /flights | Admin, Staff | required: `flight_no, departure_date, departure_time, arrival_date, arrival_time, airline_id, aircraft_id, source_airport_id, destination_airport_id`; optional `gate_id, status, fares: {"Economy":5000,"Business":14000}` |
| PUT | /flights/{id} | Admin, Staff | any field above + `actual_departure, actual_arrival` (status/delay update automatically). Setting `status:"Cancelled"` cancels all bookings and refunds them |
| DELETE | /flights/{id} | Admin | fails (409) if it has bookings |
| PUT | /flights/{id}/fares | Admin, Staff | `{"Economy": 5200}` |
| PUT | /flights/{id}/crew | Admin, Staff | `{"crew_ids":[1,2,3]}` |
| GET | /flights/{id}/seats | any | `seat_id, seat_no, class, seat_type, is_active, is_taken` - for the seat picker |
| GET | /flights/{id}/manifest | any | `{flight:{...}, passengers:[{booking_reference, passenger_name, passport_no, seat_no, class, ticket_no, check_in_status, bags, total_baggage_kg}]}` |

## Bookings, tickets, payments
| Method | Endpoint | Roles | Notes |
|---|---|---|---|
| GET | /bookings?flight_id=&passenger_id=&status=&q= | any | `q` searches PNR / passenger name / passport |
| GET | /bookings/{id} | any | booking + `payments[]`, `baggage[]`, `cancellation` |
| POST | /bookings | Admin, Staff, Agent | `{passenger_id, flight_id, seat_no, payment_mode}` (`Card/UPI/NetBanking/Cash`) -> `201 {booking_id, ticket_no, pnr}`. One call creates booking + ticket + payment |
| DELETE | /bookings/{id} | Admin, Staff, Agent | optional body `{reason}` -> `{refund_amount}` (100% if airline cancelled, else 80%) |
| GET | /tickets?booking_id=&status= | any | |
| GET | /tickets/{ticket_no} | any | full ticket details for printing (route, seat, gate, passenger, check-in status) |
| GET | /payments?ticket_id=&status=&payment_mode= | any | |
| POST | /payments | Admin, Staff, Agent | `{ticket_id, amount, payment_mode}` (extra/retry payment) |
| GET | /cancellations | any | |

## Baggage and check-in
| Method | Endpoint | Roles | Notes |
|---|---|---|---|
| GET | /baggage?booking_id=&status= | any | |
| POST | /baggage | Admin, Staff, Agent | `{booking_id, weight, baggage_type?: "Checked"/"Cabin", dimensions?}` -> `{baggage_id, baggage_tag, fee}`. Fee is automatic (15 kg free, Rs.100/extra kg); limits 32 kg checked / 7 kg cabin |
| PUT | /baggage/{id} | Admin, Staff, Agent | `{status: "Checked-In"/"Loaded"/"Arrived"/"Lost"}` |
| POST | /checkin | Admin, Staff, Agent | `{ticket_no}` |
| POST | /checkin/board | Admin, Staff, Agent | `{ticket_no}` |

## Master data (same 5 endpoints each)
`GET /x`, `GET /x/{id}`, `POST /x`, `PUT /x/{id}`, `DELETE /x/{id}` for:

| Resource | Fields | List filters | Write roles |
|---|---|---|---|
| /airlines | airline_name*, airline_code*, country, contact_no, email, is_active | country, is_active, q | Admin |
| /airports | airport_name*, airport_code*, city, country, timezone | city, country, q | Admin |
| /aircraft | aircraft_code*, capacity*, airline_id*, model, manufacturer, year_of_manufacture, status | airline_id, status, q | Admin, Staff |
| /gates | gate_no*, airport_id*, terminal, status | airport_id, status, q | Admin, Staff |
| /crew | first_name*, role*, airline_id*, last_name, license_no, phone_no | airline_id, role, q | Admin, Staff |
| /passengers | first_name*, passport_no*, last_name, dob, gender, nationality, passport_expiry, phone_no, email, address | nationality, gender, q | Admin, Staff, Agent |

(* = required). Delete is Admin only. Lists return at most 500 rows.

## Suggested screens
Login -> Dashboard (`/dashboard/stats`) -> Flight search (`/flights`) -> Seat picker (`/flights/{id}/seats`) -> Booking form (`POST /bookings`) -> Ticket view (`/tickets/{no}`) -> Check-in -> Manifest. Plus tables for passengers, baggage, payments, and (Admin) audit log.
