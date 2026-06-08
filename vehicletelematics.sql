

USE master;
GO

IF DB_ID(N'VehicleTelematicsDB') IS NOT NULL
BEGIN
    ALTER DATABASE VehicleTelematicsDB 
    SET SINGLE_USER WITH ROLLBACK IMMEDIATE;

    DROP DATABASE VehicleTelematicsDB;
END
GO

CREATE DATABASE VehicleTelematicsDB;
GO

USE VehicleTelematicsDB;
GO

--   1. CREATE ORIGINAL TABLE


CREATE TABLE dbo.VehicleLogs (
    [Timestamp] DATETIME NOT NULL,
    VIN VARCHAR(20) NOT NULL,
    Speed INT NOT NULL,
    FuelLevel INT NOT NULL,
    [Location] NVARCHAR(100) NOT NULL,
    EngineTemp INT NOT NULL,

    CONSTRAINT PK_VehicleLogs PRIMARY KEY (VIN, [Timestamp])
);
GO

   --2. GENERATE 10,000 SYNTHETIC RECORDS


;WITH Numbers AS (
    SELECT TOP (10000)
        ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM sys.objects a
    CROSS JOIN sys.objects b
)
INSERT INTO dbo.VehicleLogs (
    [Timestamp],
    VIN,
    Speed,
    FuelLevel,
    [Location],
    EngineTemp
)
SELECT
    DATEADD(MINUTE, n, '2026-05-18 08:00:00') AS [Timestamp],
    CONCAT('VIN', RIGHT('000000' + CAST(n AS VARCHAR(6)), 6)) AS VIN,
    ABS(CHECKSUM(NEWID())) % 121 AS Speed,
    5 + ABS(CHECKSUM(NEWID())) % 96 AS FuelLevel,
    CASE ABS(CHECKSUM(NEWID())) % 8
        WHEN 0 THEN N'Ho Chi Minh'
        WHEN 1 THEN N'Dong Nai'
        WHEN 2 THEN N'Binh Duong'
        WHEN 3 THEN N'Long An'
        WHEN 4 THEN N'Ba Ria Vung Tau'
        WHEN 5 THEN N'Can Tho'
        WHEN 6 THEN N'Tien Giang'
        ELSE N'Vinh Long'
    END AS [Location],
    70 + ABS(CHECKSUM(NEWID())) % 51 AS EngineTemp
FROM Numbers;
GO


--   3. CHECK ORIGINAL DATA


SELECT COUNT(*) AS OriginalRecordCount
FROM dbo.VehicleLogs;

SELECT  *
FROM dbo.VehicleLogs
ORDER BY VIN;
GO


  -- 4. HORIZONTAL FRAGMENTATION


SELECT *
INTO dbo.H1
FROM dbo.VehicleLogs
WHERE VIN BETWEEN 'VIN000001' AND 'VIN002500';

SELECT *
INTO dbo.H2
FROM dbo.VehicleLogs
WHERE VIN BETWEEN 'VIN002501' AND 'VIN005000';

SELECT *
INTO dbo.H3
FROM dbo.VehicleLogs
WHERE VIN BETWEEN 'VIN005001' AND 'VIN007500';

SELECT *
INTO dbo.H4
FROM dbo.VehicleLogs
WHERE VIN BETWEEN 'VIN007501' AND 'VIN010000';
GO

SELECT 'H1' AS FragmentName, COUNT(*) AS RecordCount FROM dbo.H1
UNION ALL
SELECT 'H2', COUNT(*) FROM dbo.H2
UNION ALL
SELECT 'H3', COUNT(*) FROM dbo.H3
UNION ALL
SELECT 'H4', COUNT(*) FROM dbo.H4;
GO


   -- 5. VERTICAL FRAGMENTATION

SELECT [Timestamp], VIN, Speed, FuelLevel, [Location]
INTO dbo.H1_Operational
FROM dbo.H1;

SELECT [Timestamp], VIN, EngineTemp
INTO dbo.H1_Diagnostic
FROM dbo.H1;

SELECT [Timestamp], VIN, Speed, FuelLevel, [Location]
INTO dbo.H2_Operational
FROM dbo.H2;

SELECT [Timestamp], VIN, EngineTemp
INTO dbo.H2_Diagnostic
FROM dbo.H2;

SELECT [Timestamp], VIN, Speed, FuelLevel, [Location]
INTO dbo.H3_Operational
FROM dbo.H3;

SELECT [Timestamp], VIN, EngineTemp
INTO dbo.H3_Diagnostic
FROM dbo.H3;

SELECT [Timestamp], VIN, Speed, FuelLevel, [Location]
INTO dbo.H4_Operational
FROM dbo.H4;

SELECT [Timestamp], VIN, EngineTemp
INTO dbo.H4_Diagnostic
FROM dbo.H4;
GO

SELECT 'H1_Operational' AS FragmentName, COUNT(*) AS RecordCount FROM dbo.H1_Operational
UNION ALL
SELECT 'H1_Diagnostic', COUNT(*) FROM dbo.H1_Diagnostic
UNION ALL
SELECT 'H2_Operational', COUNT(*) FROM dbo.H2_Operational
UNION ALL
SELECT 'H2_Diagnostic', COUNT(*) FROM dbo.H2_Diagnostic
UNION ALL
SELECT 'H3_Operational', COUNT(*) FROM dbo.H3_Operational
UNION ALL
SELECT 'H3_Diagnostic', COUNT(*) FROM dbo.H3_Diagnostic
UNION ALL
SELECT 'H4_Operational', COUNT(*) FROM dbo.H4_Operational
UNION ALL
SELECT 'H4_Diagnostic', COUNT(*) FROM dbo.H4_Diagnostic;
GO

  -- 6. RECONSTRUCTION BEFORE FAILURE

DROP TABLE IF EXISTS dbo.ReconstructedVehicleLogs;
GO

SELECT 
    o.[Timestamp],
    o.VIN,
    o.Speed,
    o.FuelLevel,
    o.[Location],
    d.EngineTemp
INTO dbo.ReconstructedVehicleLogs
FROM dbo.H1_Operational o
INNER JOIN dbo.H1_Diagnostic d
    ON o.VIN = d.VIN
   AND o.[Timestamp] = d.[Timestamp]

UNION ALL

SELECT 
    o.[Timestamp],
    o.VIN,
    o.Speed,
    o.FuelLevel,
    o.[Location],
    d.EngineTemp
FROM dbo.H2_Operational o
INNER JOIN dbo.H2_Diagnostic d
    ON o.VIN = d.VIN
   AND o.[Timestamp] = d.[Timestamp]

UNION ALL

SELECT 
    o.[Timestamp],
    o.VIN,
    o.Speed,
    o.FuelLevel,
    o.[Location],
    d.EngineTemp
FROM dbo.H3_Operational o
INNER JOIN dbo.H3_Diagnostic d
    ON o.VIN = d.VIN
   AND o.[Timestamp] = d.[Timestamp]

UNION ALL

SELECT 
    o.[Timestamp],
    o.VIN,
    o.Speed,
    o.FuelLevel,
    o.[Location],
    d.EngineTemp
FROM dbo.H4_Operational o
INNER JOIN dbo.H4_Diagnostic d
    ON o.VIN = d.VIN
   AND o.[Timestamp] = d.[Timestamp];
GO

SELECT COUNT(*) AS ReconstructedRecordCountBeforeFailure
FROM dbo.ReconstructedVehicleLogs;

SELECT 
    CASE 
        WHEN 
            (SELECT COUNT(*) FROM dbo.VehicleLogs) =
            (SELECT COUNT(*) FROM dbo.ReconstructedVehicleLogs)
        THEN 'PASS'
        ELSE 'FAIL'
    END AS ValidationResultBeforeFailure;
GO

  -- 7. FAILURE INJECTION

DROP TABLE IF EXISTS dbo.DeletedRecords;
GO

SELECT TOP 30 *
INTO dbo.DeletedRecords
FROM dbo.H3_Operational
ORDER BY NEWID();
GO

DELETE d
FROM dbo.H3_Operational d
INNER JOIN dbo.DeletedRecords r
    ON d.VIN = r.VIN
   AND d.[Timestamp] = r.[Timestamp];
GO

SELECT COUNT(*) AS DeletedRecordCount
FROM dbo.DeletedRecords;

SELECT COUNT(*) AS H2DiagnosticRemaining
FROM dbo.H3_Operational;

SELECT *
FROM dbo.DeletedRecords
ORDER BY VIN;
GO


   --8. RECONSTRUCTION AFTER FAILURE


DROP TABLE IF EXISTS dbo.ReconstructedVehicleLogs_AfterFailure;
GO

SELECT 
    o.[Timestamp],
    o.VIN,
    o.Speed,
    o.FuelLevel,
    o.[Location],
    d.EngineTemp
INTO dbo.ReconstructedVehicleLogs_AfterFailure
FROM dbo.H1_Operational o
INNER JOIN dbo.H1_Diagnostic d
    ON o.VIN = d.VIN
   AND o.[Timestamp] = d.[Timestamp]

UNION ALL

SELECT 
    o.[Timestamp],
    o.VIN,
    o.Speed,
    o.FuelLevel,
    o.[Location],
    d.EngineTemp
FROM dbo.H2_Operational o
INNER JOIN dbo.H2_Diagnostic d
    ON o.VIN = d.VIN
   AND o.[Timestamp] = d.[Timestamp]

UNION ALL

SELECT 
    o.[Timestamp],
    o.VIN,
    o.Speed,
    o.FuelLevel,
    o.[Location],
    d.EngineTemp
FROM dbo.H3_Operational o
INNER JOIN dbo.H3_Diagnostic d
    ON o.VIN = d.VIN
   AND o.[Timestamp] = d.[Timestamp]

UNION ALL

SELECT 
    o.[Timestamp],
    o.VIN,
    o.Speed,
    o.FuelLevel,
    o.[Location],
    d.EngineTemp
FROM dbo.H4_Operational o
INNER JOIN dbo.H4_Diagnostic d
    ON o.VIN = d.VIN
   AND o.[Timestamp] = d.[Timestamp];
GO

SELECT COUNT(*) AS ReconstructedRecordCountAfterFailure
FROM dbo.ReconstructedVehicleLogs_AfterFailure;
GO

  -- 9. AUTO VALIDATION REPORT

DROP TABLE IF EXISTS dbo.ValidationReport_Auto;
GO

WITH AllOperational AS (
    SELECT 'H1' AS FragmentName, [Timestamp], VIN, Speed, FuelLevel, [Location]
    FROM dbo.H1_Operational

    UNION ALL
    SELECT 'H2', [Timestamp], VIN, Speed, FuelLevel, [Location]
    FROM dbo.H2_Operational

    UNION ALL
    SELECT 'H3', [Timestamp], VIN, Speed, FuelLevel, [Location]
    FROM dbo.H3_Operational

    UNION ALL
    SELECT 'H4', [Timestamp], VIN, Speed, FuelLevel, [Location]
    FROM dbo.H4_Operational
),
AllDiagnostic AS (
    SELECT 'H1' AS FragmentName, [Timestamp], VIN, EngineTemp
    FROM dbo.H1_Diagnostic

    UNION ALL
    SELECT 'H2', [Timestamp], VIN, EngineTemp
    FROM dbo.H2_Diagnostic

    UNION ALL
    SELECT 'H3', [Timestamp], VIN, EngineTemp
    FROM dbo.H3_Diagnostic

    UNION ALL
    SELECT 'H4', [Timestamp], VIN, EngineTemp
    FROM dbo.H4_Diagnostic
),
CompareFragments AS (
    SELECT
        COALESCE(o.FragmentName, d.FragmentName) AS FragmentName,
        COALESCE(o.VIN, d.VIN) AS VIN,
        COALESCE(o.[Timestamp], d.[Timestamp]) AS [Timestamp],

        CASE
            WHEN o.VIN IS NULL THEN 'Missing Operational Record'
            WHEN d.VIN IS NULL THEN 'Missing Diagnostic Record'
        END AS ErrorType,

        CASE
            WHEN o.VIN IS NULL THEN CONCAT(d.FragmentName, '_Operational')
            WHEN d.VIN IS NULL THEN CONCAT(o.FragmentName, '_Diagnostic')
        END AS MissingFragment,

        CASE
            WHEN o.VIN IS NULL THEN 'Speed, FuelLevel, Location'
            WHEN d.VIN IS NULL THEN 'EngineTemp'
        END AS MissingColumn,

        CASE
            WHEN o.VIN IS NULL THEN 'Diagnostic record exists, but matching Operational record is missing.'
            WHEN d.VIN IS NULL THEN 'Operational record exists, but matching Diagnostic record is missing.'
        END AS [Description]
    FROM AllOperational o
    FULL OUTER JOIN AllDiagnostic d
        ON o.FragmentName = d.FragmentName
       AND o.VIN = d.VIN
       AND o.[Timestamp] = d.[Timestamp]
)
SELECT
    FragmentName,
    VIN,
    [Timestamp],
    ErrorType,
    MissingFragment,
    MissingColumn,
    [Description]
INTO dbo.ValidationReport_Auto
FROM CompareFragments
WHERE ErrorType IS NOT NULL;
GO

SELECT COUNT(*) AS ErrorCount
FROM dbo.ValidationReport_Auto;

SELECT *
FROM dbo.ValidationReport_Auto
ORDER BY FragmentName, VIN;
GO

   -- 10. FINAL VALIDATION SUMMARY

DROP TABLE IF EXISTS dbo.FinalValidationSummary;
GO

SELECT
    MissingFragment AS [Vị trí mất dữ liệu],
    ErrorType AS [Loại lỗi],
    COUNT(*) AS [Số record bị mất]
INTO dbo.FinalValidationSummary
FROM dbo.ValidationReport_Auto
GROUP BY MissingFragment, ErrorType;
GO

SELECT *
FROM dbo.FinalValidationSummary
ORDER BY [Vị trí mất dữ liệu];
GO

  -- 11. FINAL VALIDATION RESULT TABLE

SELECT 
    'Original records' AS Metric,
    CAST((SELECT COUNT(*) FROM dbo.VehicleLogs) AS VARCHAR(100)) AS Result

UNION ALL

SELECT 
    'Reconstructed records before failure',
    CAST((SELECT COUNT(*) FROM dbo.ReconstructedVehicleLogs) AS VARCHAR(100))

UNION ALL

SELECT 
    'Reconstructed records after failure',
    CAST((SELECT COUNT(*) FROM dbo.ReconstructedVehicleLogs_AfterFailure) AS VARCHAR(100))

UNION ALL

SELECT 
    'Missing records',
    CAST((SELECT COUNT(*) FROM dbo.ValidationReport_Auto) AS VARCHAR(100))

UNION ALL

SELECT 
    'Missing location',
    ISNULL(
        (
            SELECT STRING_AGG(
                CONCAT(MissingFragment, ' = ', ErrorCount, ' records'),
                '; '
            )
            FROM (
                SELECT MissingFragment, COUNT(*) AS ErrorCount
                FROM dbo.ValidationReport_Auto
                GROUP BY MissingFragment
            ) AS t
        ),
        'No missing records'
    )

UNION ALL

SELECT 
    'Validation result',
    CASE 
        WHEN (SELECT COUNT(*) FROM dbo.ValidationReport_Auto) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END;
GO