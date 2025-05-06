CREATE OR ALTER PROCEDURE sp_refresh_stgn
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @sql NVARCHAR(MAX) = N'';

    ----------------------------------------
    -- 1. Drop existing [stgn] tables
    ----------------------------------------
    SELECT @sql += 'DROP TABLE [stgn].[' + name + '];' + CHAR(13)
    FROM sys.tables
    WHERE schema_id = SCHEMA_ID('stgn');

    ----------------------------------------
    -- 2. Drop existing [stgn] views
    ----------------------------------------
    SELECT @sql += 'DROP VIEW [stgn].[' + name + '];' + CHAR(13)
    FROM sys.views
    WHERE schema_id = SCHEMA_ID('stgn');

    EXEC sp_executesql @sql;
    SET @sql = N'';



        
    ----------------------------------------
    -- 3. Create tables in [stgn] like [dbo] using INFORMATION_SCHEMA
    ----------------------------------------
    -- note using this method will not include default values for some column (ex sysdt, runid)
    -- I do not think having default values in stgn schema will be useful
    DECLARE @tableName SYSNAME;
    DECLARE @colSQL NVARCHAR(MAX);

    DECLARE table_cursor CURSOR FOR
    SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES
    WHERE TABLE_SCHEMA = 'dbo' AND TABLE_TYPE = 'BASE TABLE';

    OPEN table_cursor;
    FETCH NEXT FROM table_cursor INTO @tableName;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @colSQL = (
            SELECT STRING_AGG(
                QUOTENAME(COLUMN_NAME) + ' ' + 
                DATA_TYPE +
                CASE 
                    WHEN DATA_TYPE IN ('char', 'varchar', 'nchar', 'nvarchar') THEN 
                        '(' + 
                        CASE WHEN CHARACTER_MAXIMUM_LENGTH = -1 THEN 'MAX'
                            ELSE CAST(CHARACTER_MAXIMUM_LENGTH AS VARCHAR)
                        END + ')'
                    WHEN DATA_TYPE IN ('decimal', 'numeric') THEN
                        '(' + CAST(NUMERIC_PRECISION AS VARCHAR) + ',' + CAST(NUMERIC_SCALE AS VARCHAR) + ')'
                    ELSE ''
                END +
                CASE WHEN IS_NULLABLE = 'NO' THEN ' NOT NULL' ELSE ' NULL' END,
                ',' + CHAR(13)
            )
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_NAME = @tableName AND TABLE_SCHEMA = 'dbo'
        );

        SET @sql = 'CREATE TABLE [stgn].[' + @tableName + '] (' + CHAR(13) + @colSQL + CHAR(13) + ');';
        EXEC sp_executesql @sql;

        FETCH NEXT FROM table_cursor INTO @tableName;
    END

    CLOSE table_cursor;
    DEALLOCATE table_cursor;






    ----------------------------------------
    -- 4. Script views from [dbo] and recreate in [stgn]
    ----------------------------------------
    DECLARE @viewName SYSNAME, @viewSQL NVARCHAR(MAX);

    DECLARE view_cursor CURSOR FOR
    SELECT name FROM sys.views WHERE schema_id = SCHEMA_ID('dbo');

    OPEN view_cursor;
    FETCH NEXT FROM view_cursor INTO @viewName;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SELECT @viewSQL = OBJECT_DEFINITION(OBJECT_ID('[dbo].[' + @viewName + ']'));

        -- Replace 'CREATE VIEW [dbo].[' with 'CREATE VIEW [stgn].['
        SET @viewSQL = REPLACE(@viewSQL, 'CREATE VIEW [dbo].[', 'CREATE VIEW [stgn].[');
        SET @viewSQL = REPLACE(@viewSQL, 'CREATE VIEW [dbo].[', 'CREATE VIEW [stgn].['); -- for formatting edge cases

        EXEC sp_executesql @viewSQL;

        FETCH NEXT FROM view_cursor INTO @viewName;
    END

    CLOSE view_cursor;
    DEALLOCATE view_cursor;

    PRINT 'Schema [stgn] now mirrors [dbo] (structure only).';

END