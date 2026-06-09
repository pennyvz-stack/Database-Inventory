/******************************************************************************************
 DEMO: SQL-Native Stored Procedure Versioning (Single Stored Procedure)
 Database: AWL
 Procedure: dbo.usp_Dashboard_Healthy

 ERROR REASONS 
 -----------------------------------------
 1. Extended property missing — Trigger fails if Version property doesn't exist yet.
 2. Extended property malformed — Parser fails if Version is not in major.minor format.
 3. Permission mismatch — Developer can ALTER but cannot update extended properties.
 4. Logging tables missing — Trigger cannot insert into history or error tables.
 5. DROP timing — Extended property is gone before trigger reads it.
 6. EVENTDATA missing — Some ALTER operations don't populate EVENTDATA fully.
 7. Metadata lock — SQL Server blocks metadata updates under heavy load.
 8. Manual tampering — Someone sets Version to an invalid value.
 9. Trigger corruption — Someone edits the trigger incorrectly.


******************************************************************************************/

USE AWL;
GO

/******************************************************************************************
 STEP 0 — CLEANUP (DROP EXISTING OBJECTS AND EXTENDED PROPERTY IF THEY EXIST)
******************************************************************************************/
IF EXISTS (SELECT * FROM sys.triggers WHERE name = 'trg_LogProcedureChanges')
    DROP TRIGGER trg_LogProcedureChanges ON DATABASE;
GO

IF OBJECT_ID('dbo.StoredProcedureVersionHistory', 'U') IS NOT NULL
    DROP TABLE dbo.StoredProcedureVersionHistory;
GO

IF OBJECT_ID('dbo.TriggerErrorLog', 'U') IS NOT NULL
    DROP TABLE dbo.TriggerErrorLog;
GO

BEGIN TRY
    EXEC sys.sp_dropextendedproperty  
        @name = N'Version',
        @level0type = N'SCHEMA', @level0name = 'dbo',
        @level1type = N'PROCEDURE', @level1name = 'usp_Dashboard_Healthy';
    PRINT 'Dropped extended property Version.';
END TRY
BEGIN CATCH
    PRINT 'No existing Version property found — continuing.';
END CATCH;
GO


/******************************************************************************************
 STEP 1 — SHOW CURRENT STORED PROCEDURE (BEFORE VERSIONING)
******************************************************************************************/
SELECT 
    s.name AS SchemaName,
    p.name AS ProcedureName,
    p.create_date,
    p.modify_date
FROM sys.procedures p
JOIN sys.schemas s ON p.schema_id = s.schema_id
WHERE p.name = 'usp_Dashboard_Healthy';
GO


/******************************************************************************************
 STEP 2 — APPLY INITIAL VERSION METADATA
******************************************************************************************/
EXEC sys.sp_addextendedproperty  
    @name = N'Version',
    @value = N'1.0',
    @level0type = N'SCHEMA', @level0name = 'dbo',
    @level1type = N'PROCEDURE', @level1name = 'usp_Dashboard_Healthy';
GO


/******************************************************************************************
 STEP 3 — VERIFY EXTENDED PROPERTY
******************************************************************************************/
SELECT 
    objname AS ProcedureName,
    name AS PropertyName,
    value AS PropertyValue
FROM fn_listextendedproperty (
        NULL, 
        'SCHEMA', 'dbo', 
        'PROCEDURE', 'usp_Dashboard_Healthy', 
        NULL, NULL
    )
WHERE name = 'Version';
GO


/******************************************************************************************
 STEP 4 — CREATE THE VERSION HISTORY TABLE
******************************************************************************************/
CREATE TABLE [dbo].[StoredProcedureVersionHistory](
    [HistoryID] INT IDENTITY(1,1) NOT NULL,
    [ProcedureName] SYSNAME NOT NULL,
    [SchemaName] SYSNAME NOT NULL,
    [OldVersion] NVARCHAR(50) NULL,
    [NewVersion] NVARCHAR(50) NULL,
    [ChangedBy] NVARCHAR(128) NOT NULL,
    [ChangedOn] DATETIME2(7) NOT NULL,
    [Notes] NVARCHAR(4000) NULL,
PRIMARY KEY CLUSTERED ([HistoryID] ASC)
);
GO

ALTER TABLE [dbo].[StoredProcedureVersionHistory] 
    ADD DEFAULT (SUSER_SNAME()) FOR [ChangedBy];
GO

ALTER TABLE [dbo].[StoredProcedureVersionHistory] 
    ADD DEFAULT (SYSDATETIME()) FOR [ChangedOn];
GO


/******************************************************************************************
 STEP 5 — CREATE THE ERROR LOG TABLE
******************************************************************************************/
CREATE TABLE dbo.TriggerErrorLog (
    ErrorID INT IDENTITY(1,1) PRIMARY KEY,
    ErrorMessage NVARCHAR(4000),
    ErrorDate DATETIME DEFAULT GETDATE()
);
GO


/******************************************************************************************
 STEP 6 — CREATE THE DDL TRIGGER WITH AUTO-INCREMENT VERSIONING
******************************************************************************************/
CREATE TRIGGER trg_LogProcedureChanges
ON DATABASE
FOR CREATE_PROCEDURE, ALTER_PROCEDURE, DROP_PROCEDURE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE 
        @ProcName SYSNAME = EVENTDATA().value('(/EVENT_INSTANCE/ObjectName)[1]', 'SYSNAME'),
        @SchemaName SYSNAME = EVENTDATA().value('(/EVENT_INSTANCE/SchemaName)[1]', 'SYSNAME'),
        @EventType NVARCHAR(100) = EVENTDATA().value('(/EVENT_INSTANCE/EventType)[1]', 'NVARCHAR(100)'),
        @OldVersion NVARCHAR(50),
        @NewVersion NVARCHAR(50);

    BEGIN TRY
        -- Get current version
        SELECT @OldVersion = CAST(value AS NVARCHAR(50))
        FROM fn_listextendedproperty('Version', 'SCHEMA', @SchemaName, 'PROCEDURE', @ProcName, NULL, NULL);

        -- If no version exists, start at 1.0
        IF @OldVersion IS NULL
            SET @NewVersion = '1.0';
        ELSE
        BEGIN
            DECLARE @Major INT, @Minor INT;
            SELECT @Major = PARSENAME(@OldVersion, 2), @Minor = PARSENAME(@OldVersion, 1);
            IF @Major IS NULL SET @Major = 1;
            IF @Minor IS NULL SET @Minor = 0;
            SET @NewVersion = CONCAT(@Major, '.', @Minor + 1);
        END

        -- Update or add extended property
        BEGIN TRY
            EXEC sys.sp_updateextendedproperty  
                @name = N'Version',
                @value = @NewVersion,
                @level0type = N'SCHEMA', @level0name = @SchemaName,
                @level1type = N'PROCEDURE', @level1name = @ProcName;
        END TRY
        BEGIN CATCH
            EXEC sys.sp_addextendedproperty  
                @name = N'Version',
                @value = @NewVersion,
                @level0type = N'SCHEMA', @level0name = @SchemaName,
                @level1type = N'PROCEDURE', @level1name = @ProcName;
        END CATCH;

        -- Log the change
        INSERT INTO dbo.StoredProcedureVersionHistory
        (
            ProcedureName,
            SchemaName,
            OldVersion,
            NewVersion,
            ChangedBy,
            ChangedOn,
            Notes
        )
        VALUES
        (
            @ProcName,
            @SchemaName,
            @OldVersion,
            @NewVersion,
            SUSER_SNAME(),
            SYSDATETIME(),
            @EventType
        );
    END TRY
    BEGIN CATCH
        INSERT INTO dbo.TriggerErrorLog (ErrorMessage)
        VALUES (ERROR_MESSAGE());
    END CATCH
END;
GO


/******************************************************************************************
 STEP 7 — DEMO THE TRIGGER WORKING (ALTER #1 → Version 1.0 → 2.0)
******************************************************************************************/
ALTER PROCEDURE dbo.usp_Dashboard_Healthy
AS
BEGIN
    SELECT 'Demo change #1 at ' + CONVERT(varchar(30), SYSDATETIME());
END;
GO


/******************************************************************************************
 STEP 8 — DEMO THE TRIGGER WORKING (ALTER #2 → Version 2.0 → 3.0)
******************************************************************************************/
ALTER PROCEDURE dbo.usp_Dashboard_Healthy
AS
BEGIN
    SELECT 'Demo change #2 at ' + CONVERT(varchar(30), SYSDATETIME());
END;
GO



/******************************************************************************************
 STEP 10 — SHOW VERSION HISTORY TABLE
******************************************************************************************/
SELECT *
FROM dbo.StoredProcedureVersionHistory
WHERE ProcedureName = 'usp_Dashboard_Healthy'
ORDER BY HistoryID DESC;
GO


/******************************************************************************************
 STEP 11 — SHOW ERROR LOG (SHOULD NOW HAVE 1 ROW)
******************************************************************************************/
SELECT *
FROM dbo.TriggerErrorLog;
GO


SELECT name, is_disabled FROM sys.triggers WHERE name = 'trg_LogProcedureChanges';

USE AWL;
GO
ALTER PROCEDURE dbo.usp_Dashboard_Healthy
AS
BEGIN
    SELECT 'Trigger test fired at ' + CONVERT(varchar(30), SYSDATETIME());
END;
GO

SELECT * FROM dbo.StoredProcedureVersionHistory ORDER BY HistoryID DESC;
SELECT * FROM dbo.TriggerErrorLog ORDER BY ErrorID DESC;

PRINT 'Trigger status check:';
SELECT name, is_disabled, create_date, modify_date
FROM sys.triggers
WHERE name = 'trg_LogProcedureChanges';
GO



