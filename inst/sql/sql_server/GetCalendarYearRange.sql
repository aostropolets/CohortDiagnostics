{DEFAULT @cdm_database_schema = CDM_jmdc_v1063.dbo}

SELECT CASE
         WHEN YEAR(MIN(observation_period_start_date)) >= 2000 -- XXX case for db that go back to 90s
           THEN YEAR(MIN(observation_period_start_date))
           ELSE 2000 END                        AS start_year,
       YEAR(MAX(observation_period_end_date)) AS end_year
FROM ohdsi_cumc_deid_2019q2.dbo.observation_period;