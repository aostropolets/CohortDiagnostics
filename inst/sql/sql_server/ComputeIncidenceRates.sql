{DEFAULT @washout_period = 0} -- XXX changed from 365
{DEFAULT @first_occurrence_only = TRUE} -- XXX what if episodes, e.g. mixed?
{DEFAULT @cdm_database_schema = CDM_jmdc_v1063.dbo}
{DEFAULT @cohort_database_schema = scratch.dbo}
{DEFAULT @cohort_table = mschuemi_temp}
{DEFAULT @cohort_id = 5665}


-- XXX: ToDo:race, IP, monthly rates, change washout period (?)
-- 1. Yearly rates: Just numerator
-- 2. Yearly rates: Numerator + all patients in db
-- 3. Yearly rates: Numerator + all patients with a visit
-- 4. Yearly rates: Numerator + all patients with hosp/ED visit


IF OBJECT_ID('tempdb..#numerator', 'U') IS NOT NULL
  DROP TABLE #numerator;

SELECT YEAR(cohort_start_date) AS calendar_year,
	FLOOR((YEAR(cohort_start_date) - year_of_birth) / 10) AS age_group,
	gender_concept_id,
	COUNT(*) AS cohort_count
INTO #numerator 
FROM (
{@first_occurrence_only} ? {
	SELECT subject_id,
		MIN(cohort_start_date) AS cohort_start_date,
		MIN(cohort_end_date) AS cohort_end_date
	FROM @cohort_database_schema.@cohort_table
	WHERE cohort_definition_id = @cohort_id
	GROUP BY subject_id
 } : {
	SELECT *
	FROM @cohort_database_schema.@cohort_table
	WHERE cohort_definition_id = @cohort_id
 }
	) cohort
INNER JOIN @cdm_database_schema.person
	ON subject_id = person.person_id
INNER JOIN @cdm_database_schema.observation_period
	ON observation_period.person_id = person.person_id
		AND DATEADD(DAY, @washout_period, observation_period_start_date) <= cohort_start_date
		AND observation_period_end_date >= cohort_start_date
GROUP BY YEAR(cohort_start_date),
	FLOOR((YEAR(cohort_start_date) - year_of_birth) / 10),
	gender_concept_id;


IF OBJECT_ID('tempdb..#denominator', 'U') IS NOT NULL
  DROP TABLE #denominator;

-- 1. Incidence rates
CREATE TABLE #denominator
(
  calendar_year int,
  age_group int,
  gender_concept_id int,
  person_years bigint,
  category varchar(50)
);
-- 1.1 Incincence rates for all patients
INSERT INTO #denominator
  SELECT calendar_year,
	age_group,
	gender_concept_id,
--	race_concept_id,
	SUM(CAST(DATEDIFF(DAY, start_date, end_date) AS BIGINT)) / 365.25 AS person_years,
	'IR_all' as category
FROM (
{@first_occurrence_only} ? {
	SELECT calendar_year,
		age_group,
		gender_concept_id,
		CASE
			WHEN cohort_start_date IS NOT NULL THEN 
				CASE
					WHEN cohort_start_date < start_date THEN end_date
					ELSE cohort_start_date
				END
			ELSE start_date
		END AS start_date,
		end_date
	FROM (
}
		SELECT person.person_id,
			calendar_year,
			FLOOR((calendar_year - year_of_birth) / 10) AS age_group,
			gender_concept_id,
			CASE 
				WHEN observation_period_start_date > DATEFROMPARTS(calendar_year, 1, 1) THEN observation_period_start_date
				ELSE DATEFROMPARTS(calendar_year, 1, 1)
			END AS start_date,
			CASE 
				WHEN observation_period_end_date < DATEFROMPARTS(calendar_year + 1, 1, 1) THEN observation_period_end_date
				ELSE DATEFROMPARTS(calendar_year + 1, 1, 1)
			END AS end_date
		FROM (
			SELECT person_id,
				DATEADD(DAY, @washout_period, observation_period_start_date) AS observation_period_start_date,
				observation_period_end_date
			FROM @cdm_database_schema.observation_period
			WHERE DATEADD(DAY, @washout_period, observation_period_start_date) < observation_period_end_date
		) trunc_op
		INNER JOIN 	#calendar_years
			ON YEAR(observation_period_start_date) <= calendar_year
				AND YEAR(observation_period_end_date) >= calendar_year
		INNER JOIN @cdm_database_schema.person
			ON trunc_op.person_id = person.person_id
{@first_occurrence_only} ? {
		) time_spans_1
	LEFT JOIN (
		SELECT subject_id,
			MIN(cohort_start_date) AS cohort_start_date
		FROM @cohort_database_schema.@cohort_table
		WHERE cohort_definition_id = @cohort_id
		GROUP BY subject_id
		) cohort
	ON subject_id = person_id
		AND cohort_start_date < end_date
}
	) time_spans_2
GROUP BY calendar_year,
	age_group,
	gender_concept_id;


INSERT INTO #denominator
-- 1.2 Incincence rates for patients with any visit
SELECT calendar_year,
	age_group,
	gender_concept_id,
--	race_concept_id,
	SUM(CAST(DATEDIFF(DAY, start_date, end_date) AS BIGINT)) / 365.25 AS person_years,
	'IR_visit' as category
FROM (
{@first_occurrence_only} ? {
	SELECT calendar_year,
		age_group,
		gender_concept_id,
		CASE
			WHEN cohort_start_date IS NOT NULL THEN 
				CASE
					WHEN cohort_start_date < start_date THEN end_date
					ELSE cohort_start_date
				END
			ELSE start_date
		END AS start_date,
		end_date
	FROM (
}
		SELECT distinct person.person_id,
			calendar_year,
			FLOOR((calendar_year - year_of_birth) / 10) AS age_group,
			gender_concept_id,
			CASE 
				WHEN observation_period_start_date > DATEFROMPARTS(calendar_year, 1, 1) THEN observation_period_start_date
				ELSE DATEFROMPARTS(calendar_year, 1, 1)
			END AS start_date,
			CASE 
				WHEN observation_period_end_date < DATEFROMPARTS(calendar_year + 1, 1, 1) THEN observation_period_end_date
				ELSE DATEFROMPARTS(calendar_year + 1, 1, 1)
			END AS end_date
		FROM (
			SELECT person_id,
				DATEADD(DAY, @washout_period, observation_period_start_date) AS observation_period_start_date,
				observation_period_end_date
			FROM @cdm_database_schema.observation_period o
			WHERE DATEADD(DAY, @washout_period, observation_period_start_date) < observation_period_end_date
		) trunc_op
		INNER JOIN 	#calendar_years
			ON YEAR(observation_period_start_date) <= calendar_year
				AND YEAR(observation_period_end_date) >= calendar_year
		INNER JOIN @cdm_database_schema.person
			ON trunc_op.person_id = person.person_id
		INNER JOIN @cdm_database_schema.visit_occurrence visit 
		    ON visit.person_id = person.person_id AND YEAR(visit_start_date) = calendar_year -- any visit exists in that year
{@first_occurrence_only} ? {
		) time_spans_1
	LEFT JOIN (
		SELECT subject_id,
			MIN(cohort_start_date) AS cohort_start_date
		FROM @cohort_database_schema.@cohort_table
		WHERE cohort_definition_id = @cohort_id
		GROUP BY subject_id
		) cohort
	ON subject_id = person_id
		AND cohort_start_date < end_date
}
	) time_spans_2
GROUP BY calendar_year,
	age_group,
	gender_concept_id;



INSERT INTO #denominator
-- 1.3 Incincence rates for patients with IP/ED visit
SELECT calendar_year,
	age_group,
	gender_concept_id,
--	race_concept_id,
	SUM(CAST(DATEDIFF(DAY, start_date, end_date) AS BIGINT)) / 365.25 AS person_years,
	'IR_hosp' as category
FROM (
{@first_occurrence_only} ? {
	SELECT calendar_year,
		age_group,
		gender_concept_id,
		CASE
			WHEN cohort_start_date IS NOT NULL THEN 
				CASE
					WHEN cohort_start_date < start_date THEN end_date
					ELSE cohort_start_date
				END
			ELSE start_date
		END AS start_date,
		end_date
	FROM (
}
		SELECT distinct person.person_id,
			calendar_year,
			FLOOR((calendar_year - year_of_birth) / 10) AS age_group,
			gender_concept_id,
			CASE 
				WHEN observation_period_start_date > DATEFROMPARTS(calendar_year, 1, 1) THEN observation_period_start_date
				ELSE DATEFROMPARTS(calendar_year, 1, 1)
			END AS start_date,
			CASE 
				WHEN observation_period_end_date < DATEFROMPARTS(calendar_year + 1, 1, 1) THEN observation_period_end_date
				ELSE DATEFROMPARTS(calendar_year + 1, 1, 1)
			END AS end_date
		FROM (
			SELECT person_id,
				DATEADD(DAY, @washout_period, observation_period_start_date) AS observation_period_start_date,
				observation_period_end_date
			FROM @cdm_database_schema.observation_period o
			WHERE DATEADD(DAY, @washout_period, observation_period_start_date) < observation_period_end_date
		) trunc_op
		INNER JOIN 	#calendar_years
			ON YEAR(observation_period_start_date) <= calendar_year
				AND YEAR(observation_period_end_date) >= calendar_year
		INNER JOIN @cdm_database_schema.person
			ON trunc_op.person_id = person.person_id
		INNER JOIN @cdm_database_schema.visit_occurrence visit 
		    ON visit.person_id = person.person_id AND YEAR(visit_start_date) = calendar_year  AND visit_concept_id IN  (9203, 9201, 262)-- hosp/ED visit exists in that year
{@first_occurrence_only} ? {
		) time_spans_1
	LEFT JOIN (
		SELECT subject_id,
			MIN(cohort_start_date) AS cohort_start_date
		FROM @cohort_database_schema.@cohort_table
		WHERE cohort_definition_id = @cohort_id
		GROUP BY subject_id
		) cohort
	ON subject_id = person_id
		AND cohort_start_date < end_date
}
	) time_spans_2
GROUP BY calendar_year,
	age_group,
	gender_concept_id;


-- 2. Incidence proportion 
-- 2.1 Incincence proportion for all patients
INSERT INTO #denominator
SELECT calendar_year,
	age_group,
	gender_concept_id,
--	race_concept_id,
	COUNT(*) AS person_years,
	'IP_all' as category
FROM (
{@first_occurrence_only} ? {
	SELECT calendar_year,
		age_group,
		gender_concept_id,
		CASE
			WHEN cohort_start_date IS NOT NULL THEN 
				CASE
					WHEN cohort_start_date < start_date THEN end_date
					ELSE cohort_start_date
				END
			ELSE start_date
		END AS start_date,
		end_date
	FROM (
}
		SELECT person.person_id,
			calendar_year,
			FLOOR((calendar_year - year_of_birth) / 10) AS age_group,
			gender_concept_id,
			CASE 
				WHEN observation_period_start_date > DATEFROMPARTS(calendar_year, 1, 1) THEN observation_period_start_date
				ELSE DATEFROMPARTS(calendar_year, 1, 1)
			END AS start_date,
			CASE 
				WHEN observation_period_end_date < DATEFROMPARTS(calendar_year + 1, 1, 1) THEN observation_period_end_date
				ELSE DATEFROMPARTS(calendar_year + 1, 1, 1)
			END AS end_date
		FROM (
			SELECT person_id,
				DATEADD(DAY, @washout_period, observation_period_start_date) AS observation_period_start_date,
				observation_period_end_date
			FROM @cdm_database_schema.observation_period
			WHERE DATEADD(DAY, @washout_period, observation_period_start_date) < observation_period_end_date
		) trunc_op
		INNER JOIN 	#calendar_years
			ON YEAR(observation_period_start_date) <= calendar_year
				AND YEAR(observation_period_end_date) >= calendar_year
		INNER JOIN @cdm_database_schema.person
			ON trunc_op.person_id = person.person_id
{@first_occurrence_only} ? {
		) time_spans_1
	LEFT JOIN (
		SELECT subject_id,
			MIN(cohort_start_date) AS cohort_start_date
		FROM @cohort_database_schema.@cohort_table
		WHERE cohort_definition_id = @cohort_id
		GROUP BY subject_id
		) cohort
	ON subject_id = person_id
		AND cohort_start_date < end_date
}
	) time_spans_2
WHERE start_date<end_date
GROUP BY calendar_year,
	age_group,
	gender_concept_id;


INSERT INTO #denominator
-- 2.2 Incincence proportion for patients with any visit
SELECT calendar_year,
	age_group,
	gender_concept_id,
--	race_concept_id,
	COUNT(*) AS person_years,
	'IP_visit' as category
FROM (
{@first_occurrence_only} ? {
	SELECT calendar_year,
		age_group,
		gender_concept_id,
		CASE
			WHEN cohort_start_date IS NOT NULL THEN 
				CASE
					WHEN cohort_start_date < start_date THEN end_date
					ELSE cohort_start_date
				END
			ELSE start_date
		END AS start_date,
		end_date
	FROM (
}
		SELECT distinct person.person_id,
			calendar_year,
			FLOOR((calendar_year - year_of_birth) / 10) AS age_group,
			gender_concept_id,
			CASE 
				WHEN observation_period_start_date > DATEFROMPARTS(calendar_year, 1, 1) THEN observation_period_start_date
				ELSE DATEFROMPARTS(calendar_year, 1, 1)
			END AS start_date,
			CASE 
				WHEN observation_period_end_date < DATEFROMPARTS(calendar_year + 1, 1, 1) THEN observation_period_end_date
				ELSE DATEFROMPARTS(calendar_year + 1, 1, 1)
			END AS end_date
		FROM (
			SELECT person_id,
				DATEADD(DAY, @washout_period, observation_period_start_date) AS observation_period_start_date,
				observation_period_end_date
			FROM @cdm_database_schema.observation_period o
			WHERE DATEADD(DAY, @washout_period, observation_period_start_date) < observation_period_end_date
		) trunc_op
		INNER JOIN 	#calendar_years
			ON YEAR(observation_period_start_date) <= calendar_year
				AND YEAR(observation_period_end_date) >= calendar_year
		INNER JOIN @cdm_database_schema.person
			ON trunc_op.person_id = person.person_id
		INNER JOIN @cdm_database_schema.visit_occurrence visit 
		    ON visit.person_id = person.person_id AND YEAR(visit_start_date) = calendar_year -- any visit exists in that year
{@first_occurrence_only} ? {
		) time_spans_1
	LEFT JOIN (
		SELECT subject_id,
			MIN(cohort_start_date) AS cohort_start_date
		FROM @cohort_database_schema.@cohort_table
		WHERE cohort_definition_id = @cohort_id
		GROUP BY subject_id
		) cohort
	ON subject_id = person_id
		AND cohort_start_date < end_date
}
	) time_spans_2
WHERE start_date<end_date	
GROUP BY calendar_year,
	age_group,
	gender_concept_id;



INSERT INTO #denominator
-- 2.3 Incincence proportion for patients with IP/ED visit
SELECT calendar_year,
	age_group,
	gender_concept_id,
--	race_concept_id,
	SUM(CAST(DATEDIFF(DAY, start_date, end_date) AS BIGINT)) / 365.25 AS person_years,
	'IP_hosp' as category
FROM (
{@first_occurrence_only} ? {
	SELECT calendar_year,
		age_group,
		gender_concept_id,
		CASE
			WHEN cohort_start_date IS NOT NULL THEN 
				CASE
					WHEN cohort_start_date < start_date THEN end_date
					ELSE cohort_start_date
				END
			ELSE start_date
		END AS start_date,
		end_date
	FROM (
}
		SELECT distinct person.person_id,
			calendar_year,
			FLOOR((calendar_year - year_of_birth) / 10) AS age_group,
			gender_concept_id,
			CASE 
				WHEN observation_period_start_date > DATEFROMPARTS(calendar_year, 1, 1) THEN observation_period_start_date
				ELSE DATEFROMPARTS(calendar_year, 1, 1)
			END AS start_date,
			CASE 
				WHEN observation_period_end_date < DATEFROMPARTS(calendar_year + 1, 1, 1) THEN observation_period_end_date
				ELSE DATEFROMPARTS(calendar_year + 1, 1, 1)
			END AS end_date
		FROM (
			SELECT person_id,
				DATEADD(DAY, @washout_period, observation_period_start_date) AS observation_period_start_date,
				observation_period_end_date
			FROM @cdm_database_schema.observation_period o
			WHERE DATEADD(DAY, @washout_period, observation_period_start_date) < observation_period_end_date
		) trunc_op
		INNER JOIN 	#calendar_years
			ON YEAR(observation_period_start_date) <= calendar_year
				AND YEAR(observation_period_end_date) >= calendar_year
		INNER JOIN @cdm_database_schema.person
			ON trunc_op.person_id = person.person_id
		INNER JOIN @cdm_database_schema.visit_occurrence visit 
		    ON visit.person_id = person.person_id AND YEAR(visit_start_date) = calendar_year  AND visit_concept_id IN  (9203, 9201, 262)-- hosp/ED visit exists in that year
{@first_occurrence_only} ? {
		) time_spans_1
	LEFT JOIN (
		SELECT subject_id,
			MIN(cohort_start_date) AS cohort_start_date
		FROM @cohort_database_schema.@cohort_table
		WHERE cohort_definition_id = @cohort_id
		GROUP BY subject_id
		) cohort
	ON subject_id = person_id
		AND cohort_start_date < end_date
}
	) time_spans_2
WHERE start_date<end_date	
GROUP BY calendar_year,
	age_group,
	gender_concept_id;


IF OBJECT_ID('tempdb..#rates_summary', 'U') IS NOT NULL
  DROP TABLE #rates_summary;

create table #rates_summary
(
calendar_year int,
--calendar_month int,
age_group int,
gender varchar(20),
--race varchar(20),
cohort_count  bigint, -- change to numerator
person_years bigint,-- change to denominator
category varchar (50)
); 


INSERT INTO #rates_summary
-- Absolute numbers (numerator)
SELECT numerator.calendar_year,
	numerator.age_group,
	c.concept_name AS gender,
--	c2.concept_name as race,
	CASE 
		WHEN numerator.cohort_count IS NOT NULL THEN numerator.cohort_count
		ELSE CAST(0 AS INT)
	END AS cohort_count,
	0 as person_years, -- as we are dividing by person_years to get IR
	'absolute_n' as category
FROM #numerator numerator
INNER JOIN @cdm_database_schema.concept c 
	ON numerator.gender_concept_id = c.concept_id
--INNER JOIN @cdm_database_schema.concept c2 
--	ON numerator.race_concept_id = c2.concept_id	
;


INSERT INTO #rates_summary
-- 2. All pts/any visit/hosp or ED 
SELECT denominator.calendar_year,
	denominator.age_group,
	concept_name AS gender,
--	c2.concept_name as race,
	CASE 
		WHEN numerator.cohort_count IS NOT NULL THEN numerator.cohort_count
		ELSE CAST(0 AS INT)
	END AS cohort_count,
	person_years,
	denominator.category
FROM #denominator denominator
INNER JOIN @cdm_database_schema.concept c 
	ON denominator.gender_concept_id = c.concept_id
--INNER JOIN @cdm_database_schema.concept c2 
--	ON denominator.race_concept_id = c2.concept_id
LEFT JOIN #numerator numerator
	ON denominator.calendar_year = numerator.calendar_year
		AND denominator.age_group = numerator.age_group
		AND denominator.gender_concept_id = numerator.gender_concept_id;








TRUNCATE TABLE #calendar_years;
DROP TABLE #calendar_years;

TRUNCATE TABLE #numerator;
DROP TABLE #numerator;

TRUNCATE TABLE #denominator;
DROP TABLE #denominator;

