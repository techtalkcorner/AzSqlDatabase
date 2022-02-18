CREATE PROCEDURE [dbo].[sql_maintain_indexes] (
	@reportOnly BIT,
	@fragmentationThreshold VARCHAR(10)
	)
AS
--==========================================================================================
-- Author:      David Alzamendi (https://techtalkcorner.com)
-- Create date: 13/06/2020
-- Script that reorganizes or rebuilds all indexes having an average fragmentation 
-- percentage above a given threshold. 
-- Example: 
--			exec [dbo].[sql_maintain_indexes] @reportOnly = 0, @fragmentationThreshold= 5
--			exec [dbo].[sql_maintain_indexes] @reportOnly = 1, @fragmentationThreshold= 5
-- Parameters:
-- @reportOnly:  if set to 1: it will just generate a report with the index reorganization/rebuild statements. if set to 0: it will reorganize or rebuild the fragmented indexes
-- @fragmentationThreshold: maintains only the indexes that have average fragmentation percentage equal or higher from the given value
-- ==========================================================================================
BEGIN
	----
	BEGIN
		--
		-- Variable/parameters Declaration
		--
		DECLARE @dbname NVARCHAR(128);
		DECLARE @ReorganizeOrRebuildCommand NVARCHAR(MAX);
		DECLARE @dbid INT;
		DECLARE @indexFillFactor VARCHAR(5);
		DECLARE @indexStatisticsScanningMode VARCHAR(20);
		DECLARE @verboseMode BIT;
		DECLARE @sortInTempdb VARCHAR(3);
		DECLARE @isHadrEnabled BIT;
		DECLARE @dynamic_command NVARCHAR(1024);
		DECLARE @dynamic_command_get_tables NVARCHAR(MAX);

		--Initializations - Do not change
		SET @dynamic_command = NULL;
		SET @dynamic_command_get_tables = NULL;
		SET @isHadrEnabled = 0;
		SET NOCOUNT ON;
		---------------------------------------------------------
		--Set Parameter Values: You can change these (optional) -
		--Note: The script has default parameters set   -
		---------------------------------------------------------
		--if set to 1: it will just generate a report with the index reorganization/rebuild statements
		--if set to 0: it will reorganize or rebuild the fragmented indexes
		SET @reportOnly = isnull(@reportOnly,0);
		--maintains only the indexes that have average fragmentation percentage equal or higher from the given value
		SET @fragmentationThreshold = isnull(@fragmentationThreshold,15);
		--fill factor - the percentage of the data page to be filled up with index data
		SET @indexFillFactor = 90;
		--sets the scanning mode for index statistics 
		--available values: 'DEFAULT', NULL, 'LIMITED', 'SAMPLED', or 'DETAILED'
		SET @indexStatisticsScanningMode = 'SAMPLED';
		--if set to ON: sorts intermediate index results in TempDB 
		--if set to OFF: sorts intermediate index results in user database's log file
		SET @sortInTempdb = 'ON';
		--if set to 0: Does not output additional information about the index reorganization/rebuild process
		--if set to 0: Outputs additional information about the index reorganization/rebuild process
		SET @verboseMode = 1;

		------------------------------
		--End Parameter Values Setup -
		------------------------------

		-- Temporary table for storing index fragmentation details
		IF OBJECT_ID('tempdb..#tmpFragmentedIndexes') IS NULL
		BEGIN
			CREATE TABLE #tmpFragmentedIndexes (
				[dbName] SYSNAME
				,[tableName] SYSNAME
				,[schemaName] SYSNAME
				,[indexName] SYSNAME
				,[databaseID] SMALLINT
				,[objectID] INT
				,[indexID] INT
				,[AvgFragmentationPercentage] FLOAT
				,[reorganizationOrRebuildCommand] NVARCHAR(MAX)
				);
		END

		-- Initialize temporary table
		DELETE
		FROM #tmpFragmentedIndexes;

		-- Validate parameters/set defaults
		IF @sortInTempdb NOT IN (
				'ON'
				,'OFF'
				)
			SET @sortInTempdb = 'ON';
		-- Check if instance has AlwaysOn AGs enabled
		SET @isHadrEnabled = CAST((
					SELECT ISNULL(SERVERPROPERTY('IsHadrEnabled'), 0)
					) AS BIT);

		--
		-- Gather all tables that have indexes with 
		-- average fragmentation percentage equal or above @fragmentationThreshold
		--

		--If verbose mode is enabled, print logs
		IF @verboseMode = 1
		BEGIN
			PRINT ''
			PRINT 'Gathering index fragmentation statistics for database: [' + @dbname + '] with id: ' + CAST(@dbid AS VARCHAR(10));
		END;

			SET @dynamic_command_get_tables = N'
		 INSERT INTO #tmpFragmentedIndexes (
		  [dbName],
		  [tableName],
		  [schemaName],
		  [indexName],
		  [databaseID],
		  [objectID],
		  [indexID],
		  [AvgFragmentationPercentage],
		  [reorganizationOrRebuildCommand]  
		  )
		  SELECT
			 DB_NAME() as [dbName], 
			 tbl.name as [tableName],
			 SCHEMA_NAME (tbl.schema_id) as schemaName, 
			 idx.Name as [indexName], 
			 pst.database_id as [databaseID], 
			 pst.object_id as [objectID], 
			 pst.index_id as [indexID], 
			 pst.avg_fragmentation_in_percent as [AvgFragmentationPercentage],
			 CASE WHEN pst.avg_fragmentation_in_percent > 30 THEN 
			 ''ALTER INDEX [''+idx.Name+''] ON [''+DB_NAME()+''].[''+SCHEMA_NAME (tbl.schema_id)+''].[''+tbl.name+''] REBUILD WITH (FILLFACTOR = ' + @indexFillFactor + ', SORT_IN_TEMPDB = ' + @sortInTempdb + 
						', STATISTICS_NORECOMPUTE = OFF);''
			 WHEN pst.avg_fragmentation_in_percent > 5 AND pst.avg_fragmentation_in_percent <= 30 THEN 
			 ''ALTER INDEX [''+idx.Name+''] ON [''+DB_NAME()+''].[''+SCHEMA_NAME (tbl.schema_id)+''].[''+tbl.name+''] REORGANIZE;''     
			 ELSE
			 NULL
			 END
		  FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL , ''' + @indexStatisticsScanningMode + ''') as pst
		   INNER JOIN sys.tables as tbl ON pst.object_id = tbl.object_id
		   INNER JOIN sys.indexes idx ON pst.object_id = idx.object_id AND pst.index_id = idx.index_id
		  WHERE pst.index_id != 0  
		   AND pst.alloc_unit_type_desc IN ( N''IN_ROW_DATA'', N''ROW_OVERFLOW_DATA'')
		   AND pst.avg_fragmentation_in_percent >= ' + @fragmentationThreshold + '';

			-- if verbose  mode is enabled, print logs    
			IF @verboseMode = 1
			BEGIN
				PRINT 'Index fragmentation statistics script: ';
				PRINT @dynamic_command_get_tables;
			END

			-- gather index fragmentation statistics
			EXEC (@dynamic_command_get_tables);



		------------------------------------------------------------
		-- if 'report only' mode is enabled
		IF @reportOnly = 1
		BEGIN
			SELECT dbName
				,tableName
				,schemaName
				,indexName
				,AvgFragmentationPercentage
				,reorganizationOrRebuildCommand
			FROM #tmpFragmentedIndexes
			ORDER BY AvgFragmentationPercentage DESC;
		END
		ELSE
			-- if 'report only' mode is disabled, then execute 
			-- index reorganize/rebuild statements
		BEGIN
			DECLARE reorganizeOrRebuildCommands_cursor CURSOR
			FOR
			SELECT reorganizationOrRebuildCommand
			FROM #tmpFragmentedIndexes
			WHERE reorganizationOrRebuildCommand IS NOT NULL
			ORDER BY AvgFragmentationPercentage DESC;

			OPEN reorganizeOrRebuildCommands_cursor;

			FETCH NEXT
			FROM reorganizeOrRebuildCommands_cursor
			INTO @ReorganizeOrRebuildCommand;

			WHILE @@fetch_status = 0
			BEGIN
				IF @verboseMode = 1
				BEGIN
					PRINT ''
					PRINT 'Executing script:'
					PRINT @ReorganizeOrRebuildCommand
				END

				EXEC (@ReorganizeOrRebuildCommand);

				FETCH NEXT
				FROM reorganizeOrRebuildCommands_cursor
				INTO @ReorganizeOrRebuildCommand;
			END;

			CLOSE reorganizeOrRebuildCommands_cursor;

			DEALLOCATE reorganizeOrRebuildCommands_cursor;

			PRINT ''
			PRINT 'All fragmented indexes have been reorganized/rebuilt.'
			PRINT ''
		END
	END
	
			--End of Script
END