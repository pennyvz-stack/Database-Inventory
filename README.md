# SQL-Native Stored Procedure Versioning

This project provides a lightweight, robust framework for tracking version numbers of SQL Server stored procedures directly within the database. It utilizes **Extended Properties** to hold version metadata and a **Database-Level DDL Trigger** to automatically increment versions whenever a procedure is modified.

---

## 🚀 Features

* **Automated Versioning:** Automatically bumps the version number (e.g., 1.0 $\rightarrow$ 1.1) upon `CREATE`, `ALTER`, or `DROP` operations.
* **Audit Trail:** Keeps a history of all changes in a dedicated audit table (`StoredProcedureVersionHistory`).
* **Error Resilience:** Includes a dedicated error log table (`TriggerErrorLog`) to capture failures in the trigger mechanism without crashing the DDL operation.
* **Zero Dependencies:** Runs entirely on native SQL Server features; no external tools required.

---

## 🛠 Setup & Usage

### 1. Database Initialization
Ensure you are in the context of your target database (e.g., `USE AWL;`).

### 2. Execution Order
The provided script is sequential. Run the sections in order to set up your environment:
1.  **Cleanup:** Removes existing trigger/table assets to ensure a clean slate.
2.  **Metadata Setup:** Applies initial `1.0` version to your target procedure.
3.  **Table Creation:** Creates the history and error logging tables.
4.  **Trigger Activation:** Deploys the `trg_LogProcedureChanges` DDL trigger.

### 3. Verification
After installation, you can verify functionality by altering your procedure:

```sql
ALTER PROCEDURE dbo.usp_Dashboard_Healthy
AS
BEGIN
    SELECT 'Trigger test fired' AS Status;
END;
GO

Check the results:
SELECT * FROM dbo.StoredProcedureVersionHistory ORDER BY ChangedOn DESC;

⚠️ Gotchas & Troubleshooting

When implementing DDL triggers for versioning, be aware of these common failure points derived from the script's error handling logic:

Potential IssueS:

Missing Extended Property -- Trigger may fail if the initial Version property is not explicitly set.

Malformed Metadata -- Parsing fails if the Version format is not major.minor.

Permission Mismatch -- The user running the ALTER must have permissions to update extended properties.

Metadata Lock -- High load environments may experience blocking when the trigger attempts to update system metadata.

Trigger Corruption -- If the trigger itself is modified improperly, the logging mechanism will fail.

If you suspect an issue, check the dbo.TriggerErrorLog table:
SELECT * FROM dbo.TriggerErrorLog;

📋 License & Contributing
This script is provided as a utility for database administrators and developers to improve traceability in SQL Server environments. Feel free to adapt the trigger logic for specific naming conventions or additional audit requirements.