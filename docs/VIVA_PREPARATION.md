# Viva preparation

## Project introduction

The Airport Flight and Passenger Management System is a small operations application that stores airport, airline, aircraft, flight, passenger, booking, ticket, payment, and baggage data in MySQL. Staff use a browser interface served by Flask. The database enforces core relationships and booking rules.

## Problem statement and objectives

Manual or disconnected records can create duplicate passenger details, invalid schedules, and conflicting seat assignments. The project demonstrates a relational design with referential integrity, SQL reporting, stored procedures, triggers, and a Flask JSON API. It supports flight lookup, passenger records, reservations, ticket/payment history, baggage, and operational reporting.

## Architecture and ER model

The frontend uses same-origin `fetch()` calls to Flask routes. Flask validates the request, applies role checks, and calls parameterized SQL or stored procedures. MySQL stores the data and enforces integrity. See [ER_DIAGRAM.md](ER_DIAGRAM.md) and [RELATIONAL_SCHEMA.md](RELATIONAL_SCHEMA.md) for the implemented entities and keys.

## Schema, keys, and normalization

Surrogate primary keys identify rows. Foreign keys connect flight to airline/aircraft/airports, booking to passenger/flight/seat, and ticket/payment/baggage to their parent records. Unique keys protect airport/airline codes, passport numbers, ticket numbers, and one seat assignment per flight. Tables separate repeating groups: `FLIGHT_CREW` resolves the flight/crew many-to-many relationship and `FLIGHT_FARE` stores fares by class. This supports 3NF with deliberate historical snapshots and seat counters described in the relational schema.

## SQL features and transactions

The project uses joins to combine descriptive data, aggregation for dashboard/revenue/occupancy reports, and parameterized filters for searches. Stored procedures encapsulate flight search, seat maps, manifests, booking, cancellation, check-in, and dashboard statistics. Triggers enforce rules that span rows and maintain audit, fare counters, cancellations, and baggage fees. `sp_book_ticket` locks a flight row and wraps booking, ticket, and payment creation in one transaction; failures roll back all related writes.

## Why Flask and MySQL?

Flask provides a small Python HTTP layer that is straightforward to connect to HTML/JavaScript and parameterized MySQL queries. MySQL supports relational constraints, transactions, triggers, and procedures required to demonstrate DBMS concepts. Both are widely taught and work well for a compact academic project.

## Limitations

This is an academic demonstration, not an airline reservation product. Sample accounts must be replaced; payment records are simulated and do not connect to a payment gateway. The SQL setup drops and recreates its named database and must only run against disposable development data. Live database tests require a separate configured test instance. The UI covers a practical subset of the API rather than every table and operation.

## Likely viva questions

1. **What problem does the system solve?** It keeps airport operation and passenger reservation data in a linked database and applies consistent rules to common workflows.
2. **Why use a relational database?** Records have clear relationships and need constraints, joins, and transactions.
3. **What is a primary key?** A column or set of columns that uniquely identifies each row.
4. **What is a foreign key?** A constraint requiring a reference to an existing parent key (or NULL when allowed).
5. **What is a candidate key?** A minimal attribute set that uniquely identifies a row; for example, `airport_code`.
6. **What does 1:N mean?** One parent can be related to multiple child rows, such as one passenger having multiple bookings.
7. **How is M:N crew assignment represented?** With `FLIGHT_CREW`, containing one flight/crew pair per assignment.
8. **Why is a seat stored separately?** It validates seat identity and class, prevents aircraft seat duplication, and supports seat-map queries.
9. **How is duplicate seat assignment prevented?** A unique key on `(flight_id, seat_id)` plus booking procedure locking and validation.
10. **How can a cancelled seat be reused?** Cancellation sets its booking's `seat_id` to NULL while preserving the booking row; the unique key then permits reuse.
11. **What is normalization?** Organizing relations to reduce avoidable duplication and update anomalies.
12. **How does the schema approach 3NF?** Each relation stores attributes that depend on its key; repeating crew and fare groups are modeled as separate relations.
13. **What is an INNER JOIN?** It returns matching rows from both inputs; flight listings use joins for airline and airport names.
14. **What is a LEFT JOIN?** It keeps every left-side row and includes matching right-side values where present; useful for gates or bookings that lack optional child records.
15. **What do GROUP BY and HAVING do?** GROUP BY forms aggregate groups; HAVING filters those groups after aggregation.
16. **What is a stored procedure?** A named database program that can accept parameters and perform SQL operations, such as `sp_book_ticket`.
17. **What is a trigger?** Database logic that runs automatically on a table event, such as validating a flight insert.
18. **What is a transaction?** A set of operations treated as one unit with commit or rollback.
19. **How does the booking transaction help?** It prevents a booking from being committed without its ticket/payment and uses a row lock to serialize same-flight seat allocation.
20. **What does ACID stand for?** Atomicity, Consistency, Isolation, Durability.
21. **How is SQL injection reduced?** Values use MySQL Connector parameter placeholders; dynamic CRUD identifiers come from fixed server-side whitelists.
22. **How are passwords stored?** The login and user-management routes use Werkzeug password hashing rather than plaintext.
23. **What does the audit log contain?** Database actions and before/after snapshots where a trigger writes them, with the acting application user when known.
24. **How are refunds handled?** Cancellation triggers mark payment records refunded and record the computed refund; the procedure returns that value.
25. **Why use `DECIMAL` for money?** It stores fixed-point decimal values without binary floating-point representation errors.
26. **Why are departure date and time separate?** The schedule is modeled in distinct SQL date and time columns, while cross-midnight flights compare both date and time.
27. **What is a CHECK constraint?** A row-level Boolean condition enforced by supported MySQL versions, such as positive capacity.
28. **What does the API do?** It validates requests, enforces roles, routes database work, and returns JSON/status codes to the browser.
29. **What is the main security configuration rule?** Keep DB credentials and signing secrets in environment configuration, outside source control.
30. **What is the main operational limitation?** The provided schema initializer drops its database, so it must only be run on disposable development data.

## Faculty demonstration sequence

1. Show the ER diagram and explain the Flight–Booking–Passenger relationships.
2. Start Flask and show `/api/health` reporting a database connection.
3. Sign in with a configured demo account and show dashboard numbers from MySQL.
4. Search flights by origin, destination, and date; open the seat map/manifest API if asked.
5. Create a demonstration passenger, then create a booking using an available seat and a simulated payment method.
6. Show the returned PNR and ticket number, then locate the booking and ticket.
7. Attempt the same seat again to demonstrate the database rule (use only a test database).
8. Cancel the demonstration booking and explain how the procedure/triggers release the seat and store the refund.
9. Show baggage, payment, and audit records, then discuss constraints, transaction boundaries, and limitations.
