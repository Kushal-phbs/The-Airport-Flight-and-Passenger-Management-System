-- =====================================================================
-- Airport Flight and Passenger Management System
-- schema.sql  (MySQL 8.0.16+ required for CHECK constraints)
-- Run in MySQL Workbench: File > Open SQL Script > Execute (lightning icon)
-- =====================================================================

DROP DATABASE IF EXISTS airport_db;
CREATE DATABASE airport_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE airport_db;

-- ---------------------------------------------------------------------
-- SECURITY / USERS
-- ---------------------------------------------------------------------
CREATE TABLE USER_ACCOUNT (
    user_id        INT AUTO_INCREMENT PRIMARY KEY,
    username       VARCHAR(50)  NOT NULL UNIQUE,
    password_hash  VARCHAR(255) NOT NULL,
    role           ENUM('Admin','Staff','Agent') NOT NULL DEFAULT 'Staff',
    email          VARCHAR(100) UNIQUE,
    is_active      BOOLEAN NOT NULL DEFAULT TRUE,
    created_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_login     TIMESTAMP NULL
) ENGINE=InnoDB;

CREATE TABLE AUDIT_LOG (
    log_id      INT AUTO_INCREMENT PRIMARY KEY,
    user_id     INT NULL,
    action      VARCHAR(50)  NOT NULL,
    table_name  VARCHAR(50),
    record_id   INT,
    old_value   TEXT,
    new_value   TEXT,
    log_time    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_audit_user FOREIGN KEY (user_id)
        REFERENCES USER_ACCOUNT(user_id) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- MASTER DATA
-- ---------------------------------------------------------------------
CREATE TABLE AIRLINE (
    airline_id    INT AUTO_INCREMENT PRIMARY KEY,
    airline_name  VARCHAR(100) NOT NULL,
    airline_code  VARCHAR(10)  NOT NULL UNIQUE,
    country       VARCHAR(60),
    contact_no    VARCHAR(20),
    email         VARCHAR(100),
    is_active     BOOLEAN NOT NULL DEFAULT TRUE
) ENGINE=InnoDB;

CREATE TABLE AIRPORT (
    airport_id    INT AUTO_INCREMENT PRIMARY KEY,
    airport_name  VARCHAR(120) NOT NULL,
    city          VARCHAR(60),
    country       VARCHAR(60),
    airport_code  VARCHAR(10) NOT NULL UNIQUE,
    timezone      VARCHAR(50)
) ENGINE=InnoDB;

CREATE TABLE AIRCRAFT (
    aircraft_id         INT AUTO_INCREMENT PRIMARY KEY,
    aircraft_code       VARCHAR(20) NOT NULL UNIQUE,
    model               VARCHAR(60),
    manufacturer        VARCHAR(60),
    year_of_manufacture YEAR,
    capacity            INT NOT NULL,
    status              ENUM('Active','Maintenance','Retired') NOT NULL DEFAULT 'Active',
    airline_id          INT NOT NULL,
    CONSTRAINT chk_aircraft_capacity CHECK (capacity > 0),
    CONSTRAINT fk_aircraft_airline FOREIGN KEY (airline_id)
        REFERENCES AIRLINE(airline_id) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE SEAT (
    seat_id      INT AUTO_INCREMENT PRIMARY KEY,
    aircraft_id  INT NOT NULL,
    seat_no      VARCHAR(5) NOT NULL,
    `class`      ENUM('Economy','Business','First') NOT NULL DEFAULT 'Economy',
    seat_type    ENUM('Window','Aisle','Middle'),
    is_active    BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT uq_seat_aircraft UNIQUE (aircraft_id, seat_no),
    CONSTRAINT fk_seat_aircraft FOREIGN KEY (aircraft_id)
        REFERENCES AIRCRAFT(aircraft_id) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE GATE (
    gate_id     INT AUTO_INCREMENT PRIMARY KEY,
    gate_no     VARCHAR(10) NOT NULL,
    terminal    VARCHAR(10),
    status      ENUM('Available','Occupied','Closed') NOT NULL DEFAULT 'Available',
    airport_id  INT NOT NULL,
    CONSTRAINT uq_gate UNIQUE (airport_id, terminal, gate_no),
    CONSTRAINT fk_gate_airport FOREIGN KEY (airport_id)
        REFERENCES AIRPORT(airport_id) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE CREW (
    crew_id     INT AUTO_INCREMENT PRIMARY KEY,
    first_name  VARCHAR(50) NOT NULL,
    last_name   VARCHAR(50),
    role        ENUM('Pilot','Co-Pilot','Attendant') NOT NULL,
    license_no  VARCHAR(30) UNIQUE,
    phone_no    VARCHAR(20),
    airline_id  INT NOT NULL,
    CONSTRAINT fk_crew_airline FOREIGN KEY (airline_id)
        REFERENCES AIRLINE(airline_id) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE PASSENGER (
    passenger_id     INT AUTO_INCREMENT PRIMARY KEY,
    first_name       VARCHAR(50) NOT NULL,
    last_name        VARCHAR(50),
    dob              DATE,
    gender           ENUM('Male','Female','Other'),
    nationality      VARCHAR(50),
    passport_no      VARCHAR(20) NOT NULL UNIQUE,
    passport_expiry  DATE,
    phone_no         VARCHAR(20),
    email            VARCHAR(100),
    address          VARCHAR(255),
    created_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- FLIGHT OPERATIONS
-- ---------------------------------------------------------------------
CREATE TABLE FLIGHT (
    flight_id               INT AUTO_INCREMENT PRIMARY KEY,
    flight_no               VARCHAR(10) NOT NULL,
    departure_date          DATE NOT NULL,
    departure_time          TIME NOT NULL,
    arrival_date            DATE NOT NULL,
    arrival_time            TIME NOT NULL,
    actual_departure        DATETIME NULL,
    actual_arrival          DATETIME NULL,
    delay_minutes           INT NOT NULL DEFAULT 0,
    status                  ENUM('Scheduled','Boarding','Departed','Arrived','Delayed','Cancelled')
                            NOT NULL DEFAULT 'Scheduled',
    airline_id              INT NOT NULL,
    aircraft_id             INT NOT NULL,
    source_airport_id       INT NOT NULL,
    destination_airport_id  INT NOT NULL,
    gate_id                 INT NULL,
    CONSTRAINT uq_flight UNIQUE (flight_no, departure_date),
    -- NOTE: "source_airport_id <> destination_airport_id" cannot be a CHECK here
    -- (MySQL error 3823: FK columns with referential actions). It is enforced
    -- by a BEFORE INSERT/UPDATE trigger on FLIGHT in triggers.sql.
    CONSTRAINT chk_flight_times CHECK (
        arrival_date > departure_date
        OR (arrival_date = departure_date AND arrival_time > departure_time)),
    CONSTRAINT fk_flight_airline FOREIGN KEY (airline_id)
        REFERENCES AIRLINE(airline_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_flight_aircraft FOREIGN KEY (aircraft_id)
        REFERENCES AIRCRAFT(aircraft_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_flight_source FOREIGN KEY (source_airport_id)
        REFERENCES AIRPORT(airport_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_flight_dest FOREIGN KEY (destination_airport_id)
        REFERENCES AIRPORT(airport_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_flight_gate FOREIGN KEY (gate_id)
        REFERENCES GATE(gate_id) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE FLIGHT_FARE (
    fare_id          INT AUTO_INCREMENT PRIMARY KEY,
    flight_id        INT NOT NULL,
    `class`          ENUM('Economy','Business','First') NOT NULL,
    base_price       DECIMAL(10,2) NOT NULL,
    seats_available  INT,
    CONSTRAINT chk_fare_price CHECK (base_price >= 0),
    CONSTRAINT uq_flight_class UNIQUE (flight_id, `class`),
    CONSTRAINT fk_fare_flight FOREIGN KEY (flight_id)
        REFERENCES FLIGHT(flight_id) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE FLIGHT_CREW (
    flight_id  INT NOT NULL,
    crew_id    INT NOT NULL,
    PRIMARY KEY (flight_id, crew_id),
    CONSTRAINT fk_fc_flight FOREIGN KEY (flight_id)
        REFERENCES FLIGHT(flight_id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_fc_crew FOREIGN KEY (crew_id)
        REFERENCES CREW(crew_id) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- BOOKING / TICKETING
-- ---------------------------------------------------------------------
CREATE TABLE BOOKING (
    booking_id         INT AUTO_INCREMENT PRIMARY KEY,
    booking_reference  VARCHAR(10) NOT NULL UNIQUE,          -- PNR
    booking_date       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    booking_status     ENUM('Confirmed','Pending','Cancelled') NOT NULL DEFAULT 'Pending',
    total_amount       DECIMAL(10,2) NOT NULL DEFAULT 0,
    passenger_id       INT NOT NULL,
    flight_id          INT NOT NULL,
    seat_id            INT NULL,                              -- NULL after cancellation
    booked_by          INT NULL,
    CONSTRAINT chk_booking_amount CHECK (total_amount >= 0),
    CONSTRAINT uq_flight_seat UNIQUE (flight_id, seat_id),
    CONSTRAINT fk_booking_passenger FOREIGN KEY (passenger_id)
        REFERENCES PASSENGER(passenger_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_booking_flight FOREIGN KEY (flight_id)
        REFERENCES FLIGHT(flight_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_booking_seat FOREIGN KEY (seat_id)
        REFERENCES SEAT(seat_id) ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT fk_booking_user FOREIGN KEY (booked_by)
        REFERENCES USER_ACCOUNT(user_id) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE TICKET (
    ticket_id    INT AUTO_INCREMENT PRIMARY KEY,
    ticket_no    VARCHAR(20) NOT NULL UNIQUE,
    issue_date   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fare_amount  DECIMAL(10,2) NOT NULL,
    status       ENUM('Issued','Cancelled','Refunded') NOT NULL DEFAULT 'Issued',
    booking_id   INT NOT NULL UNIQUE,
    CONSTRAINT chk_ticket_fare CHECK (fare_amount >= 0),
    CONSTRAINT fk_ticket_booking FOREIGN KEY (booking_id)
        REFERENCES BOOKING(booking_id) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE PAYMENT (
    payment_id      INT AUTO_INCREMENT PRIMARY KEY,
    payment_date    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    amount          DECIMAL(10,2) NOT NULL,
    currency        CHAR(3) NOT NULL DEFAULT 'INR',
    payment_mode    ENUM('Card','UPI','NetBanking','Cash') NOT NULL,
    transaction_id  VARCHAR(40) UNIQUE,
    status          ENUM('Success','Failed','Pending','Refunded') NOT NULL DEFAULT 'Pending',
    ticket_id       INT NOT NULL,
    CONSTRAINT chk_payment_amount CHECK (amount > 0),
    CONSTRAINT fk_payment_ticket FOREIGN KEY (ticket_id)
        REFERENCES TICKET(ticket_id) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE BAGGAGE (
    baggage_id    INT AUTO_INCREMENT PRIMARY KEY,
    baggage_tag   VARCHAR(20) NOT NULL UNIQUE,
    baggage_type  ENUM('Checked','Cabin') NOT NULL DEFAULT 'Checked',
    weight        DECIMAL(5,2) NOT NULL,
    dimensions    VARCHAR(30),
    fee           DECIMAL(8,2) NOT NULL DEFAULT 0,
    status        ENUM('Checked-In','Loaded','Arrived','Lost') NOT NULL DEFAULT 'Checked-In',
    booking_id    INT NOT NULL,
    CONSTRAINT chk_baggage_weight CHECK (weight > 0),
    CONSTRAINT fk_baggage_booking FOREIGN KEY (booking_id)
        REFERENCES BOOKING(booking_id) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE CHECK_IN (
    checkin_id       INT AUTO_INCREMENT PRIMARY KEY,
    ticket_id        INT NOT NULL UNIQUE,
    check_in_time    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    boarding_time    DATETIME NULL,
    boarding_status  ENUM('Checked-In','Boarded','No-Show') NOT NULL DEFAULT 'Checked-In',
    CONSTRAINT fk_checkin_ticket FOREIGN KEY (ticket_id)
        REFERENCES TICKET(ticket_id) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE CANCELLATION (
    cancel_id      INT AUTO_INCREMENT PRIMARY KEY,
    booking_id     INT NOT NULL UNIQUE,
    cancel_date    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    reason         VARCHAR(255),
    refund_amount  DECIMAL(10,2) NOT NULL DEFAULT 0,
    processed_by   INT NULL,
    CONSTRAINT chk_cancel_refund CHECK (refund_amount >= 0),
    CONSTRAINT fk_cancel_booking FOREIGN KEY (booking_id)
        REFERENCES BOOKING(booking_id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_cancel_user FOREIGN KEY (processed_by)
        REFERENCES USER_ACCOUNT(user_id) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- EXTRA INDEXES (foreign keys are indexed automatically by InnoDB)
-- ---------------------------------------------------------------------
CREATE INDEX idx_flight_date      ON FLIGHT (departure_date);
CREATE INDEX idx_flight_route     ON FLIGHT (source_airport_id, destination_airport_id, departure_date);
CREATE INDEX idx_passenger_name   ON PASSENGER (last_name, first_name);
CREATE INDEX idx_booking_status   ON BOOKING (booking_status);
CREATE INDEX idx_audit_time       ON AUDIT_LOG (log_time);

-- Verify: should list 18 tables
SHOW TABLES;
