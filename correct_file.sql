CREATE USER dean_academics WITH PASSWORD 'iitropar';
CREATE USER academics_office WITH PASSWORD 'iitropar';

CREATE DATABASE AIMS;

CREATE TABLE course_catalog (
    course_id VARCHAR(10) PRIMARY KEY,
    course_title VARCHAR(255) NOT NULL,
    lecture INTEGER NOT NULL,
    tutorial INTEGER NOT NULL,
    practical INTEGER NOT NULL,
    self_study FLOAT NOT NULL,
    credits FLOAT NOT NULL
);

CREATE TABLE student_database (
    entry_number VARCHAR(15) PRIMARY KEY,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    course VARCHAR(100) NOT NULL,
    branch VARCHAR(100) NOT NULL,
    year INTEGER NOT NULL,
    credits_completed FLOAT NOT NULL,
    cgpa FLOAT NOT NULL
);

CREATE TABLE faculty_database (
    faculty_id SERIAL PRIMARY KEY,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    department VARCHAR(100) NOT NULL
);

CREATE TABLE time_table_slots (
    id SERIAL PRIMARY KEY,
    day VARCHAR(10) NOT NULL,
    beginning TIME NOT NULL,
    ending TIME NOT NULL
);

CREATE TABLE course_offering (
    offering_id VARCHAR(255) PRIMARY KEY,
    faculty_id INTEGER NOT NULL REFERENCES faculty_database(faculty_id),
    course_id VARCHAR(10) NOT NULL REFERENCES course_catalog(course_id),
    semester INTEGER NOT NULL,
    year INTEGER NOT NULL,
    time_slot INTEGER [] NOT NULL
);


CREATE TABLE student_credit_info (
    entry_number VARCHAR(15) PRIMARY KEY REFERENCES student_database(entry_number),
    last_semester FLOAT,
    second_last_semester FLOAT,
    maximum_credits_allowed FLOAT NOT NULL
);

CREATE TABLE batchwise_FA_list (
    course VARCHAR(100) NOT NULL,
    branch VARCHAR(100) NOT NULL,
    year INTEGER NOT NULL,
    faculty_id INTEGER REFERENCES faculty_database(faculty_id) NOT NULL,
    PRIMARY KEY (course, branch, year)
);

CREATE TABLE dean_ticket_table (
    ticket_id VARCHAR(255) PRIMARY KEY,
    entry_number VARCHAR(15) NOT NULL REFERENCES student_database(entry_number),
    extra_credits_required FLOAT NOT NULL,
    status VARCHAR(255) NOT NULL
);

GRANT SELECT, INSERT, DELETE, UPDATE ON course_catalog TO academics_office;
GRANT SELECT, INSERT, DELETE, UPDATE ON faculty_database TO academics_office;
GRANT SELECT, INSERT, DELETE, UPDATE ON student_database TO academics_office;
GRANT SELECT, INSERT, DELETE, UPDATE ON student_credit_info TO academics_office;
GRANT SELECT, INSERT, DELETE, UPDATE ON time_table_slots TO academics_office;
GRANT SELECT, INSERT, DELETE, UPDATE ON course_offering TO academics_office;
GRANT SELECT, INSERT, DELETE, UPDATE ON batchwise_FA_list TO academics_office;
GRANT USAGE, SELECT ON SEQUENCE time_table_slots_id_seq TO academics_office;
GRANT USAGE, SELECT ON SEQUENCE faculty_database_id_seq TO academics_office;

GRANT SELECT ON course_catalog TO dean_academics;
GRANT SELECT, INSERT, DELETE, UPDATE ON dean_ticket_table TO dean_academics;

CREATE OR REPLACE FUNCTION add_time_table_slots (
    IN day VARCHAR(10),
    IN beginning TIME,
    IN ending TIME
) RETURNS VOID AS $$
    BEGIN
        IF SESSION_USER != 'academics_office' THEN
            RAISE EXCEPTION 'Only the academics office can add time table slots.';
        END IF;
        INSERT INTO time_table_slots (day, beginning, ending)
        VALUES (day, beginning, ending);
    END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION student_registration (
    IN first_name VARCHAR(100),
    IN last_name VARCHAR(100),
    IN entry_number VARCHAR(15),
    IN course VARCHAR(100),
    IN branch VARCHAR(100),
    IN year INTEGER,
    IN credits_completed FLOAT,
    IN cgpa FLOAT
) RETURNS VOID AS $$
DECLARE
    faculty_advisor INTEGER;
BEGIN

    -- make a new user with student entry number
    EXECUTE format ('CREATE USER %I WITH PASSWORD ''iitropar'';', entry_number);

    -- add this in past semester credits table

    INSERT INTO student_database VALUES (entry_number, first_name, last_name, course, branch, year, credits_completed, cgpa);

    INSERT INTO student_credit_info VALUES (entry_number, NULL, NULL, 18);

    -- make a table for past courses of this student
    EXECUTE format (
        'CREATE TABLE %I (
            faculty_id INT NOT NULL REFERENCES faculty_database(faculty_id),
            course_id VARCHAR(10) NOT NULL REFERENCES course_catalog(course_id),
            year INT NOT NULL,
            semester INT NOT NULL,
            status VARCHAR(255) NOT NULL,
            grade INT NOT NULL,
            PRIMARY KEY (faculty_id, course_id, year, semester)
        );', 'student_past_courses_' || entry_number
    );

    EXECUTE format ('GRANT SELECT ON TABLE %I TO %I', 'student_past_courses_' || entry_number, entry_number);
    EXECUTE format ('GRANT SELECT, INSERT, DELETE, UPDATE ON TABLE %I TO "academics_office"', 'student_past_courses_' || entry_number, entry_number);

    EXECUTE format ('SELECT faculty_id FROM batchwise_FA_list WHERE course = %L AND year = %L AND branch = %L', course, year, branch) INTO faculty_advisor;
    -- raise notice 'fac_id: %', faculty_advisor;

    EXECUTE format ('GRANT SELECT ON TABLE %I TO %I', 'student_past_courses_' || entry_number, faculty_advisor);

    -- make a table for current courses of this student
    EXECUTE format (
        'CREATE TABLE %I (
            faculty_id INT REFERENCES faculty_database(faculty_id),
            course_id VARCHAR(10) REFERENCES course_catalog(course_id),
            semester INT,
            year INT,
            PRIMARY KEY (faculty_id, course_id, semester, year)
        );', 'student_current_courses_' || entry_number
    );

    EXECUTE format ('GRANT SELECT ON TABLE %I TO %I', 'student_current_courses_' || entry_number, entry_number);
    EXECUTE format ('GRANT SELECT, INSERT, DELETE, UPDATE ON TABLE %I TO "academics_office"', 'student_current_courses_' || entry_number, entry_number);
    EXECUTE format ('GRANT SELECT ON TABLE %I TO %I', 'student_current_courses_' || entry_number, faculty_advisor);

    -- make a table for ticket for this student
    -- ticket id = entry number_semester_year
    EXECUTE format (
        'CREATE TABLE %I (
            ticket_id VARCHAR(255) PRIMARY KEY,
            extra_credits_required FLOAT NOT NULL,
            semester INT NOT NULL,
            year INT NOT NULL,
            status VARCHAR(255) NOT NULL
        );', 'student_ticket_table_' || entry_number
    );

    EXECUTE format ('GRANT SELECT ON TABLE %I TO %I', 'student_ticket_table_' || entry_number, entry_number);
    EXECUTE format ('GRANT SELECT, INSERT, DELETE, UPDATE ON TABLE %I TO "academics_office"', 'student_ticket_table_' || entry_number, entry_number);

    EXECUTE format (
        'CREATE TRIGGER %I
        BEFORE INSERT ON %I
        FOR EACH ROW
        EXECUTE PROCEDURE student_course_registration_trigger();
        ', 'student_course_registration_trigger_' || entry_number, 'student_current_courses_' || entry_number
    );

    EXECUTE format ('GRANT SELECT ON TABLE course_offering TO %I', entry_number);
END
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION faculty_registration (
    IN faculty_id INTEGER,
    IN first_name VARCHAR(100),
    IN last_name VARCHAR(100),
    IN department VARCHAR(100)
) RETURNS VOID AS $$
BEGIN
    -- make a new user with faculty id
    EXECUTE format ('CREATE USER %I WITH PASSWORD ''iitropar'';', faculty_id);

    INSERT INTO faculty_database VALUES (faculty_id, first_name, last_name, department);

    -- make a table for course offering of this faculty
    EXECUTE format (
        'CREATE TABLE %I (
            course_id VARCHAR(15) REFERENCES course_catalog(course_id),
            semester INT,
            year INT,
            time_slots INT [] NOT NULL,
            PRIMARY KEY (course_id, semester, year)
        );', 'course_offering_' || faculty_id
    );

    EXECUTE format ('GRANT SELECT, INSERT, DELETE ON TABLE %I TO %I', 'course_offering_' || faculty_id, faculty_id);
    EXECUTE format ('GRANT SELECT ON TABLE %I TO "academics_office"', 'course_offering_' || faculty_id, faculty_id);

    -- make a table for FA
    EXECUTE format (
        'CREATE TABLE %I (
            ticket_id VARCHAR(255) PRIMARY KEY,
            entry_number VARCHAR(15) NOT NULL REFERENCES student_database(entry_number),
            extra_credits_required FLOAT NOT NULL,
            status VARCHAR(255) NOT NULL
        );', 'FA_ticket_table_' || faculty_id
    );

    EXECUTE format ('GRANT SELECT ON TABLE %I TO %I', 'FA_ticket_table_' || faculty_id, faculty_id);
    EXECUTE format ('GRANT SELECT ON TABLE %I TO "academics_office"', 'FA_ticket_table_' || faculty_id, faculty_id);

END
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION faculty_course_offering (
    IN course_id VARCHAR(15),
    IN semester INTEGER,
    IN year INTEGER,
    IN time_slots INTEGER []
) RETURNS VOID AS $$
DECLARE
    faculty_id INTEGER;
    faculty_id_string VARCHAR(10);
    offering_id VARCHAR(255);
    session_user VARCHAR(255);
    student_entry_number VARCHAR(15);
BEGIN
    -- add the course offering to common course offering table
    SELECT SESSION_USER INTO faculty_id;
    SELECT faculty_id || '_' || course_id || '_' || semester || '_' || year INTO offering_id;

    EXECUTE format ('INSERT INTO course_offering VALUES (%L, %L, %L, %L, %L, %L)', offering_id, faculty_id, course_id, semester, year, time_slots);

    -- add into the course offering table of the faculty
    EXECUTE format (
        'INSERT INTO %I VALUES (%L, %L, %L, %L);',
        'course_offering_' || faculty_id, course_id, semester, year, time_slots
    );

    -- create a table for batchwise cg criteria
    EXECUTE format (
        'CREATE TABLE %I (
            course VARCHAR(100) NOT NULL,
            branch VARCHAR(100) NOT NULL,
            year INTEGER NOT NULL,
            cg FLOAT NOT NULL,
            PRIMARY KEY (course, branch, year)
        );', offering_id || '_batchwise_cg_criteria'
    );

    EXECUTE format ('GRANT SELECT, UPDATE, DELETE, INSERT ON TABLE %I TO %I', offering_id || '_batchwise_cg_criteria', faculty_id);

    EXECUTE format (
        'CREATE TABLE %I (
            course_id VARCHAR(10) PRIMARY KEY REFERENCES course_catalog(course_id)
        );', offering_id || '_prereq'
    );

    EXECUTE format ('GRANT SELECT, UPDATE, DELETE, INSERT ON TABLE %I TO %I', offering_id || '_prereq', faculty_id);

    EXECUTE format (
        'CREATE TABLE %I (
            entry_number VARCHAR(15) PRIMARY KEY REFERENCES student_database(entry_number)
        );', offering_id || '_students'
    );

    -- -- --- ---- --- make extra functions
    EXECUTE format ('GRANT SELECT, DELETE, INSERT ON TABLE %I TO %I', offering_id || '_students', faculty_id);

    FOR student_entry_number IN
        SELECT entry_number FROM student_database
    LOOP
        EXECUTE format ('GRANT SELECT ON TABLE %I TO %I', offering_id || '_batchwise_cg_criteria', student_entry_number);
        EXECUTE format ('GRANT SELECT ON TABLE %I TO %I', offering_id || '_prereq', student_entry_number);
        EXECUTE format ('GRANT SELECT ON TABLE %I TO %I', offering_id || '_students', student_entry_number);
    END LOOP;
END
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION set_prereq(
    IN offering_id VARCHAR(10),
    IN prereq_id VARCHAR(10) []
) RETURNS VOID AS $$
DECLARE
    id VARCHAR(10);
BEGIN
    FOREACH id IN ARRAY prereq_id
    LOOP
        EXECUTE format ('INSERT INTO %I VALUES (%L)', offering_id || '_prereq', id);
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION student_course_registration_trigger (
) RETURNS TRIGGER AS $$
DECLARE
    total_credits INTEGER;
    maximum_credit_limit FLOAT;
    student_course RECORD;
    student_batch RECORD;
    batches RECORD;
    batch_exist INTEGER;
    new_slots INTEGER [];
    courses RECORD;
    entry_number VARCHAR(15);
    courses_time_slot INTEGER [];
    slot INTEGER;
    new_slot INTEGER;
    course_credits INTEGER;
    new_course_credits INTEGER;
    new_course_offering_id VARCHAR(255);
    prereq_not_done INTEGER;
BEGIN
    SELECT SESSION_USER INTO entry_number;
    total_credits := 0;
    -- this loop will count total_credits
    FOR student_course IN
        EXECUTE format('SELECT * FROM %I', 'student_current_courses_' || entry_number)
    LOOP
        SELECT credits 
        FROM course_catalog
        WHERE student_course.course_id = course_catalog.course_id INTO course_credits;
        total_credits := total_credits + course_credits;
    END LOOP;

    -- extracting maximum credit limit
    EXECUTE format (
        'SELECT maximum_credits_allowed FROM student_credit_info WHERE entry_number = %L',
        entry_number
    ) INTO maximum_credit_limit;

    -- checking if the limit is satisfied
    EXECUTE format ('SELECT credits FROM course_catalog WHERE course_id = %L', NEW.course_id) INTO new_course_credits;

    IF (total_credits + new_course_credits > maximum_credit_limit) THEN
        RAISE EXCEPTION 'You have exceeded the maximum credits limit.' USING ERRCODE = 'FATAL';
    END IF;

    -- checking the cg criteria
    EXECUTE format ('SELECT offering_id FROM course_offering WHERE course_id = %L AND faculty_id = %L', NEW.course_id, NEW.faculty_id) INTO new_course_offering_id;

    FOR student_batch IN
        EXECUTE format ('SELECT * FROM student_database WHERE entry_number = %L', entry_number)
    LOOP
        FOR batches IN
            EXECUTE format ('SELECT * FROM %I', new_course_offering_id || '_batchwise_cg_criteria')
        LOOP
            IF batches.year = student_batch.year AND batches.course = student_batch.course AND batches.branch = student_batch.branch THEN
                IF batches.cg > student_batch.cgpa THEN
                    RAISE EXCEPTION 'You dont satisfy the cg criteria' USING ERRCODE = 'FATAL';
                END IF;
            END IF;
        END LOOP;

        -- if the batch doesn't exist
        EXECUTE format ('SELECT count(*) FROM %I WHERE year = %L AND course = %L AND branch = %L', new_course_offering_id || '_batchwise_cg_criteria', student_batch.year, student_batch.course, student_batch.branch) INTO batch_exist;
        IF (batch_exist = 0) THEN
            RAISE EXCEPTION 'Your batch is not allowed to register for this course' USING ERRCODE = 'FATAL';
        END IF;
    END LOOP;

    SELECT time_slot FROM course_offering WHERE course_id = NEW.course_id AND faculty_id = NEW.faculty_id AND semester = NEW.semester AND year = NEW.year INTO new_slots;

    FOR courses IN
        EXECUTE format('SELECT * FROM %I', 'student_current_courses_' || entry_number)
    LOOP
        FOR courses_time_slot IN 
            EXECUTE format ('SELECT time_slot FROM course_offering WHERE course_id = %L', courses.course_id)
        LOOP
            FOREACH slot IN ARRAY courses_time_slot
            LOOP
                FOREACH new_slot IN ARRAY new_slots
                LOOP
                    IF new_slot = slot THEN
                        RAISE EXCEPTION 'This course have time overlap with some other registered course' USING ERRCODE = 'FATAL';
                    END IF;
                END LOOP;
            END LOOP;
        END LOOP;
    END LOOP;

    -- checking prereq
    EXECUTE format ('SELECT count(*) FROM (
        SELECT course_id FROM %I 
        EXCEPT
        SELECT course_id FROM %I WHERE status = ''Completed'') AS num_prereq_not_done', 
        new_course_offering_id || '_prereq', 'student_past_courses_' || entry_number
    ) INTO prereq_not_done;

    IF (prereq_not_done > 0) THEN
        RAISE EXCEPTION 'You havent done all the prerequisites of the course' USING ERRCODE = 'FATAL';
    END IF;

    EXECUTE format (
        'INSERT INTO %I VALUES (%L)', new_course_offering_id || '_students', entry_number
    );

    RETURN NEW;
END
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION student_course_registration (
    IN faculty_id INTEGER,
    IN course_id VARCHAR(10),
    IN semester INTEGER,
    IN year INTEGER
) RETURNS VOID AS $$
DECLARE
    entry_number VARCHAR(15);
BEGIN
    -- add the course offering to common course offering table
    SELECT SESSION_USER INTO entry_number;

    EXECUTE format (
        'INSERT INTO %I VALUES (%L, %L, %L, %L);',
        'student_current_courses_' || entry_number, faculty_id, course_id, semester, year
    );

END
$$ LANGUAGE plpgsql SECURITY DEFINER;

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
    SELECT SESSION_USER INTO faculty_id;
    EXECUTE format (
        'INSERT INTO %I VALUES (%L, %L, %L, %L);',
        faculty_id || '_' || course_id || '_' || semester || '_' || year || '_batchwise_cg_criteria', course, branch, year_of_joining, cgpa
    );
END
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION student_ticket_generator (
    IN extra_credits_required FLOAT,
    IN semester INTEGER,
    IN year INTEGER
) RETURNS VOID AS $$
DECLARE
    entry_number VARCHAR(15);
    faculty_id INT;
    student RECORD;
BEGIN
    -- add ticket to student ticket table
    SELECT SESSION_USER INTO entry_number;

    EXECUTE format ('INSERT INTO %I VALUES(%L, %L, %L, %L, %L);', 'student_ticket_table_' || entry_number, entry_number || '_' || semester || '_' || year, extra_credits_required, semester, year, 'Awaiting FA Approval');

    EXECUTE format ('SELECT l.faculty_id FROM student_database s, batchwise_FA_list l WHERE s.entry_number = %L and l.branch = s.branch and l.year = s.year and l.course = s.course', entry_number) INTO faculty_id;
    -- add ticket to FA's table
    FOR student IN
        EXECUTE format ('SELECT * FROM student_database WHERE entry_number = %L', entry_number)
    LOOP
        EXECUTE format ('SELECT faculty_id FROM batchwise_FA_list WHERE course = %L and branch = %L and year = %L', student.course, student.branch, student.year) INTO faculty_id;
    END LOOP;

    EXECUTE format ('INSERT INTO %I VALUES(%L, %L, %L, %L);', 'FA_ticket_table_' || faculty_id, entry_number || '_' || semester || '_' || year, entry_number, extra_credits_required, 'Awaiting Approval');
END
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION FA_acceptance (
    IN ticket_id VARCHAR(100),
    IN entry_number VARCHAR(15)
) RETURNS VOID AS $$
DECLARE
    extra_credits_required FLOAT;
    faculty_id INT;
BEGIN
    -- update status in student ticket table
    EXECUTE format (
        'UPDATE %I 
         SET status = %L
         WHERE ticket_id = %L;', 'student_ticket_table_' || entry_number, 'Awaiting dean approval', ticket_id
    );

    -- update status in FAs ticket table
    SELECT SESSION_USER INTO faculty_id;
    EXECUTE format (
        'UPDATE %I 
         SET status = %L
         WHERE ticket_id = %L;', 'FA_ticket_table_' || faculty_id, 'Approved', ticket_id
    );

    -- update status in student's ticket table
    EXECUTE format(
        'SELECT extra_credits_required
        FROM %I
        WHERE ticket_id = %L', 'student_ticket_table_' || entry_number, ticket_id
    ) INTO extra_credits_required;

    EXECUTE format (
        'INSERT INTO dean_ticket_table VALUES(%L, %L, %L, %L)', ticket_id, entry_number, extra_credits_required, 'Awaiting Approval'
    );
END
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION FA_rejection (
    IN ticket_id VARCHAR(100),
    IN entry_number VARCHAR(15)
) RETURNS VOID AS $$
DECLARE
    faculty_id INT;
BEGIN
    -- update status in student ticket table
    EXECUTE format (
        'UPDATE %I 
         SET status = %L
         WHERE ticket_id = %L;', 'student_ticket_table_' || entry_number, 'Rejected by FA', ticket_id
    );

    -- update status in FAs ticket table
    SELECT SESSION_USER INTO faculty_id;
    EXECUTE format (
        'UPDATE %I 
         SET status = %L
         WHERE ticket_id = %L;', 'FA_ticket_table_' || faculty_id, 'Rejected', ticket_id
    );
END
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION dean_acceptance (
    IN ticket_id VARCHAR(255),
    IN entry_number VARCHAR(15)
) RETURNS VOID AS $$
DECLARE
    extra_credits_required FLOAT;
BEGIN
    -- update status in student ticket table
    IF SESSION_USER != 'dean_academics' THEN
        RAISE EXCEPTION 'Only the dean can approve the ticket';
    END IF;

    EXECUTE format (
        'UPDATE %I 
         SET status = %L
         WHERE ticket_id = %L;', 'student_ticket_table_' || entry_number, 'Approved', ticket_id
    );

    -- update status in dean's table
    EXECUTE format (
        'UPDATE dean_ticket_table
         SET status = %L
         WHERE ticket_id = %L;', 'Approved', ticket_id
    );

    EXECUTE format(
        'SELECT extra_credits_required
        FROM %I
        WHERE ticket_id = %L', 'student_ticket_table_' || entry_number, ticket_id
    ) INTO extra_credits_required;
    -- update max credit limit for the student
    EXECUTE format (
        'UPDATE student_credit_info
         SET maximum_credits_allowed = maximum_credits_allowed + %L
         WHERE entry_number = %L;', extra_credits_required, entry_number
    );
END
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION dean_rejection (
    IN ticket_id VARCHAR(255),
    IN entry_number VARCHAR(15)
) RETURNS VOID AS $$
BEGIN
    -- update status in student ticket table
    IF SESSION_USER != 'dean_academics' THEN
        RAISE EXCEPTION 'Only the dean can reject the ticket';
    END IF;

    EXECUTE format (
        'UPDATE %I
         SET status = %L
         WHERE ticket_id = %L;', 'student_ticket_table_' || entry_number, 'Rejected by dean', ticket_id
    );

    -- update status in dean's table
    EXECUTE format (
        'UPDATE dean_ticket_table
         SET status = %L
         WHERE ticket_id = %L;', 'Rejected', ticket_id
    );
END
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION student_drop_course (
    IN course_id VARCHAR(15),
    IN faculty_id INT,
    IN semester INT,
    IN year INT
) RETURNS VOID AS $$
BEGIN
    -- delete from student_current_courses
    EXECUTE format (
        'DELETE FROM %I
         WHERE course_id = %L
         AND faculty_id = %L
         AND semester = %L
         AND year = %L;', 'student_current_courses_' || CURRENT_USER, course_id, faculty_id, semester, year
    );
END
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION grade_uploading (
    IN course_id VARCHAR(10),
    IN file_path VARCHAR(1000)
) RETURNS VOID AS $$
DECLARE
    course_entry RECORD;
    current_course_iterator RECORD;
    store_data_temp RECORD;
    result VARCHAR(15);
    course_credits FLOAT;
    present_credits FLOAT;
    current_cgpa FLOAT;
    final_cgpa FLOAT;
BEGIN
    CREATE TABLE student_grade (
        entry_number VARCHAR(15),
        grade INTEGER
    );

    EXECUTE format ('COPY student_grade FROM %L DELIMITER '','' CSV HEADER', file_path);
    -- agr ye na chale to
    -- \copy student_grade FROM file_path DELIMITER ',' CSV;
    EXECUTE format (
        'SELECT credits FROM course_catalog WHERE course_id = %L', course_id
    ) INTO course_credits;
    
    FOR course_entry IN
        SELECT * FROM student_grade
    LOOP
        FOR current_course_iterator IN 
            EXECUTE format ('SELECT * FROM %I', 'student_current_courses_' || course_entry.entry_number)
        LOOP
            IF current_course_iterator.course_id = course_id THEN
                store_data_temp = current_course_iterator;
                EXIT;
            END IF;
        END LOOP;

        IF course_entry.grade < 5 THEN
            result = 'Failed';
        ELSE
            result = 'Completed';
        END IF;

        EXECUTE format (
            'INSERT INTO %I VALUES(%L, %L, %L, %L, %L, %L);', 'student_past_courses_' || course_entry.entry_number, store_data_temp.faculty_id, store_data_temp.course_id, store_data_temp.year, store_data_temp.semester, result, course_entry.grade
        );

        EXECUTE format (
            'SELECT credits_completed FROM student_database WHERE entry_number = %L', course_entry.entry_number
        ) INTO present_credits;

        EXECUTE format (
            'SELECT cgpa FROM student_database WHERE entry_number = %L', course_entry.entry_number
        ) INTO current_cgpa;

        final_cgpa = (current_cgpa * present_credits) + (course_credits * course_entry.grade);
        final_cgpa = final_cgpa / (present_credits + course_credits);

        EXECUTE format (
            'UPDATE student_database SET credits_completed = credits_completed + %L WHERE entry_number = %L', course_credits, course_entry.entry_number
        );

        EXECUTE format (
            'UPDATE student_database SET cgpa = %L WHERE entry_number = %L', final_cgpa, course_entry.entry_number
        );

        EXECUTE format ('DELETE FROM %I WHERE course_id = %L;','student_current_courses_' || course_entry.entry_number, course_id);

    END LOOP;
    DROP TABLE student_grade;
END
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION report_generation (
    IN entry_number VARCHAR(15),
    IN required_semester INT,
    IN required_year INT
) RETURNS TABLE (
    course_id VARCHAR,
    grade INTEGER,
    credits INTEGER
) AS $$
DECLARE
    course_entry RECORD;
    temp_credits FLOAT;
    report_entry RECORD;
    sgpa_numerator FLOAT;
    sgpa FLOAT;
    cgpa FLOAT;
    student_name VARCHAR(200);
    student_entry_number VARCHAR(15);
    credits_completed FLOAT;
    report_semester INTEGER;
    report_year INTEGER;
    first_name VARCHAR(100);
    last_name VARCHAR(100);
BEGIN
    IF SESSION_USER != 'academics_office' THEN
        RAISE EXCEPTION 'Only the academics office can generate the report';
    END IF;

    student_entry_number = entry_number;
    EXECUTE format ('SELECT first_name FROM student_database WHERE entry_number = %L', student_entry_number) INTO first_name;
    EXECUTE format ('SELECT last_name FROM student_database WHERE entry_number = %L', student_entry_number) INTO last_name;

    student_name = first_name || ' ' || last_name;

    report_semester = required_semester;
    report_year = required_year;
    credits_completed = 0;

    DROP TABLE IF EXISTS student_report;

    CREATE TABLE student_report (
        course_id VARCHAR(10),
        grade INTEGER,
        credits INTEGER
    );

    FOR course_entry IN
        EXECUTE format ('SELECT * FROM %I', 'student_past_courses_' || entry_number)
    LOOP
        IF course_entry.semester = required_semester AND course_entry.year = required_year THEN

            temp_credits = 0;

            IF course_entry.grade > 5 THEN
                EXECUTE format ('SELECT credits FROM course_catalog WHERE course_id = %L', course_entry.course_id) INTO temp_credits;
                credits_completed = credits_completed + temp_credits;
            END IF;

            EXECUTE format (
                'INSERT INTO student_report VALUES(%L, %L, %L);', course_entry.course_id, course_entry.grade, temp_credits
            );

        END IF;
    END LOOP;

    sgpa_numerator = 0;

    FOR report_entry IN
        SELECT * FROM student_report
    LOOP
        sgpa_numerator = sgpa_numerator + report_entry.credits * report_entry.grade;
    END LOOP;
    
    IF credits_completed = 0 THEN
        sgpa = 0;
    ELSE
        sgpa = sgpa_numerator / credits_completed;
    END IF;
    --cgpa store me se uthani h

    EXECUTE format ('SELECT cgpa FROM student_database WHERE entry_number = %L', student_entry_number) INTO cgpa;
    raise notice 'Student name: %', student_name;
    raise notice 'Entry number: %', student_entry_number;
    raise notice 'cgpa: %', cgpa;
    raise notice 'sgpa: %', sgpa;
    RETURN QUERY SELECT * FROM student_report;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;