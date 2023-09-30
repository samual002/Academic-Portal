CREATE USER dean_acads WITH PASSWORD 'iitropar';
CREATE USER acads_office WITH PASSWORD 'iitropar';

CREATE DATABASE AIMS;

CREATE TABLE course_catalog (
    course_id VARCHAR(10) UNIQUE PRIMARY KEY,
    course_title VARCHAR(255) NOT NULL,
    lecture INT NOT NULL,
    tutorial INT NOT NULL,
    practical INT NOT NULL,
    self_study FLOAT NOT NULL,
    credits FLOAT NOT NULL
);

CREATE TABLE course_prereq (
    course_id VARCHAR(10) NOT NULL,
    prereq_id VARCHAR(10) NOT NULL,
    PRIMARY KEY (course_id, prereq_id),
    FOREIGN KEY (course_id) REFERENCES course_catalog(course_id),
    FOREIGN KEY (prereq_id) REFERENCES course_catalog(course_id)
); -- course_id is the course that has prereqs, prereq_id is the prereq

CREATE TABLE course_offering (
    offering_id VARCHAR(255) UNIQUE PRIMARY KEY,
    faculty_id INT NOT NULL,
    course_id VARCHAR(10) NOT NULL,
    semester INT NOT NULL,
    year INT NOT NULL,
    time_slot INT [] NOT NULL
);

CREATE TABLE student_credit_info (
    entry_number VARCHAR(15) NOT NULL,
    last_semester INT,
    second_last_semester INT,
    total_credits INT
);

GRANT SELECT, UPDATE, INSERT, DELETE ON course_catalog TO dean_acads;
GRANT SELECT, UPDATE, INSERT, DELETE ON course_catalog TO acads_office;

GRANT SELECT, UPDATE, INSERT, DELETE ON course_prereq TO dean_acads;
GRANT SELECT, UPDATE, INSERT, DELETE ON course_prereq TO acads_office;

GRANT SELECT, UPDATE, INSERT, DELETE ON course_offering TO dean_acads;
GRANT SELECT, UPDATE, INSERT, DELETE ON course_offering TO acads_office;

GRANT SELECT, UPDATE, INSERT, DELETE ON student_past_semester_credits TO dean_acads;
GRANT SELECT, UPDATE, INSERT, DELETE ON student_past_semester_credits TO acads_office;

CREATE OR REPLACE FUNCTION student_course_registration_trigger (
) RETURNS TRIGGER AS $$
DECLARE
    total_credits INT;
    past_credits RECORD;
    current_user VARCHAR(15);
BEGIN
    SELECT CURRENT_USER INTO current_user;
    total_credits := 0;

    EXECUTE format (
        'FOR student_course IN SELECT * FROM  student_current_courses_%I
        LOOP
            total_credits := total_credits + student_course.credits
        END LOOP;

        SELECT * INTO past_credits FROM student_past_semester_credits WHERE entry_number = %I;

        IF ((total_credits + NEW.credits) > average) THEN
            RAISE EXCEPTION ''You have exceeded the maximum credits limit.'' USING ERRCODE = ''FATAL''
        END IF;

        FOR student_batch IN SELECT * FROM student_database WHERE entry_number = %I;
        LOOP
            FOR batches IN SELECT * FROM %I
            LOOP
                IF batches.year = student_batch.year AND batches.course = student_batch.course AND batches.branch = student_batch.branch THEN
                    IF batches.cg > student_batch.cg THEN
                        RAISE EXCEPTION ''You dont satisfy the cg criteria'' USING ERRCODE = ''FATAL''
                    END IF;
                END IF;
            END LOOP;

            IF (SELECT * FROM %I WHERE year = student_batch.year AND course = student_batch.course AND branch = student_batch.branch = NULL) THEN
                RAISE EXCEPTION ''Your batch is not allowed to register for this course'' USING ERRCODE = ''FATAL''
            END IF;
        END LOOP;

        SELECT time_slots FROM course_offering WHERE course_id = NEW.course_id AND faculty_id = NEW.faculty_id AND semester = NEW.semester AND year = NEW.year INTO new_slots;

        FOR courses IN SELECT * FROM %I
        LOOP
            FOR courses_time_slot IN SELECT time_slot FROM course_offering WHERE course_id = courses.course_id
            LOOP
                FOREACH slot IN ARRAY courses_time_slot
                LOOP
                    FOREACH new_slot IN ARRAY new_slots
                    LOOP
                        IF new_slot = slot THEN
                            RAISE EXCEPTION ''This course have time overlap with some other registered course'' USING ERRCODE = ''FATAL''
                        END IF;
                    END LOOP;
                END LOOP;
            END LOOP;
        END LOOP;', current_user, current_user, current_user, NEW.faculty_id || '_' || NEW.course_id || '_' || NEW.semester || '_' || NEW.year, NEW.faculty_id || '_' || NEW.course_id || '_' || NEW.semester || '_' || NEW.year, 'student_current_courses_' || current_user
    );
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION student_registration (
    IN first_name VARCHAR(100),
    IN last_name VARCHAR(100),
    IN entry_number VARCHAR(15),
    IN course VARCHAR(100),
    IN branch VARCHAR(100),
    IN year INT,
    IN credits_completed FLOAT,
    IN cgpa FLOAT
) RETURNS VOID AS $$
BEGIN

    -- make a new user with student entry number
    EXECUTE format ('CREATE USER %I WITH PASSWORD ''iitropar'';', entry_number);

    -- add this in past semester credits table
    INSERT INTO student_credit_info VALUES (entry_number, NULL, NULL);

    INSERT INTO student_database VALUES (first_name, last_name, entry_number, course, branch, year, credits_completed, cgpa);

    -- make a table for past courses of this student
    EXECUTE format (
        'CREATE TABLE %I (
            faculty_id INT NOT NULL,
            course_id VARCHAR(10) NOT NULL,
            year INT NOT NULL,
            semester INT NOT NULL,
            status VARCHAR(255) NOT NULL,
            grade INT NOT NULL
        );', 'student_past_courses_' || entry_number
    );

    -- make a table for current courses of this student
    EXECUTE format (
        'CREATE TABLE %I (
            faculty_id INT NOT NULL,
            course_id VARCHAR(10) NOT NULL,
            semester INT NOT NULL,
            year INT NOT NULL
        );', 'student_current_courses_' || entry_number
    );

    -- make a table for ticket for this student
    -- ticket id = entry number_semester_year
    EXECUTE format (
        'CREATE TABLE %I (
            ticket_id VARCHAR(255) NOT NULL,
            extra_credits_required FLOAT NOT NULL,
            semester INT NOT NULL,
            year INT NOT NULL,
            status VARCHAR(255) NOT NULL
        );', 'student_ticket_table_' || entry_number
    );


    -- EXECUTE format (
    --     'GRANT SELECT ON %I TO %I', 
    --     'student_past_courses_' || entry_number, entry_number
    -- );

    -- EXECUTE format (
    --     'GRANT SELECT, INSERT, UPDATE, DELETE ON %I TO %I', 
    --     'student_current_courses_' || entry_number, entry_number
    -- );

    -- EXECUTE format (
    --     'GRANT SELECT, INSERT ON %I TO %I', 
    --     'student_ticket_table_' || entry_number, entry_number
    -- );

    -- what if there are not last semester and second last semester?
    -- take the course id
    -- check if the course is in the course_catalog
    -- check the credits of the course

    EXECUTE format (
        'CREATE TRIGGER student_course_registration_trigger_%I
        BEFORE INSERT ON student_current_courses_%I
        FOR EACH ROW
        EXECUTE PROCEDURE student_course_registration_trigger()', entry_number, entry_number
    );

    -- check cgpa criteria


END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION faculty_registration (
    IN faculty_id INT
) RETURNS VOID AS $$
BEGIN

    -- make a new user with faculty id
    EXECUTE format ('CREATE USER %I WITH PASSWORD ''iitropar'';', faculty_id);

    -- make a table for course offering of this faculty
    EXECUTE format (
        'CREATE TABLE %I (
            course_id VARCHAR(15) NOT NULL,
            semester INT NOT NULL,
            year INT NOT NULL,
            time_slots INT [] NOT NULL,
        );', 'course_offering_' || faculty_id
    );

    -- make a table for FA
    EXECUTE format (
        'CREATE TABLE %I (
            ticket_id VARCHAR(255) NOT NULL,
            entry_number VARCHAR(15) NOT NULL,
            extra_credits_required FLOAT NOT NULL,
            status VARCHAR(255) NOT NULL
        );', 'FA_ticket_table_' || faculty_id
    );

    -- EXECUTE format (
    --     'GRANT SELECT, UPDATE, INSERT, DELETE ON %I TO %I', 
    --     'course_offering_' || faculty_id, faculty_id
    -- );

END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION faculty_course_offering_table (
    IN course_id VARCHAR(15),
    IN semester INT,
    IN year INT,
    IN time_slots INT []
) RETURNS VOID AS $$
DECLARE
    faculty_id INT;
BEGIN
    -- add the course offering to common course offering table
    SELECT CURRENT_USER INTO faculty_id;
    EXECUTE format (
        'INSERT INTO course_offering VALUES (%I, faculty_id, course_id, semester, year, time_slots);',
        faculty_id || '_' || course_id || '_' || semester || '_' || year
    );

    -- add into the course offering table of the faculty
    EXECUTE format (
        'INSERT INTO %I VALUES (course_id, semester, year, time_slots);',
        'course_offering_' || faculty_id
    );

    -- create a table for batchwise cg criteria
    EXECUTE format (
        'CREATE TABLE %I (
            course VARCHAR(255) NOT NULL,
            branch VARCHAR(255) NOT NULL,
            year INT NOT NULL,
            cg FLOAT NOT NULL
        );', faculty_id || '_' || course_id || '_' || semester || '_' || year
    );

    -- EXECUTE format (
    --     'GRANT SELECT, UPDATE, INSERT, DELETE ON %I TO %I', 
    --     faculty_id || '_' || course_id || '_' || semester || '_' || year, faculty_id
    -- );

END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION batchwise_cg_criteria (
    IN course_id VARCHAR(15),
    IN semester INT,
    IN year INT,
    IN course VARCHAR(100),
    IN branch VARCHAR(100),
    IN year_of_joining INT,
    IN cgpa FLOAT
) RETURNS VOID AS $$
DECLARE
    faculty_id INT;
BEGIN
    -- add into the course offering table of the faculty
    SELECT CURRENT_USER INTO faculty_id;
    EXECUTE format (
        'INSERT INTO %I VALUES (course, branch, year_of_joining, cgpa);',
        faculty_id || '_' || course_id || '_' || semester || '_' || year
    );

    -- EXECUTE format (
    --     'GRANT SELECT, UPDATE, INSERT, DELETE ON %I TO %I', 
    --     faculty_id || '_' || course_id || '_' || semester || '_' || year, faculty_id
    -- );

END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION student_course_registration (
    IN faculty_id INT,
    IN course_id VARCHAR(15),
    IN semester INT,
    IN year INT
) RETURNS VOID AS $$
DECLARE
    entry_number VARCHAR(15);
BEGIN
    -- add the course offering to common course offering table
    SELECT CURRENT_USER INTO entry_number;

    EXECUTE format (
        'INSERT INTO %I VALUES (%L, %L, %L, %L);',
        'student_current_courses_' || entry_number, faculty_id, course_id, semester, year     
    );

END
$$ LANGUAGE plpgsql;