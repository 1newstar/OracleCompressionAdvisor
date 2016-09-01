------------------------------------------------------------------------------------------
---------------------------------- Compression Advisor -----------------------------------
-- Author: gvenzl (c) 2016 (v)1.0.1
-- This package provides an easy to use interface for Oracle Compression Advisor (DBMS_COMPRESSION)
-- It does not change any data or structure in any way nor does DBMS_COMPRESSION
-- However, to get an accurate estimate of the compression rates that could be achieved,
-- it has to be executed against production like data.
------------------------------------------------------------------------------------------

CREATE OR REPLACE PACKAGE BODY COMPRESSION_ADVISOR
AS
-- Local variables
   v_compression_stats   compression_stats := compression_stats();
   v_verbose_output      verbose_output := verbose_output();
   v_blkcnt_cmp          PLS_INTEGER;
   v_blkcnt_uncmp        PLS_INTEGER;
   v_row_cmp             PLS_INTEGER;
   v_row_uncmp           PLS_INTEGER;
   v_cmp_ratio           NUMBER;
   v_comptype_str        VARCHAR2(100);
   
   b_SchemaAnalysis      BOOLEAN   := FALSE;
   
   -- Exceptions
   TABLE_OR_VIEW_DOES_NOT_EXIST   EXCEPTION;
   PRAGMA EXCEPTION_INIT (TABLE_OR_VIEW_DOES_NOT_EXIST, -942);
   
   NOT_ENOUGH_ROWS                EXCEPTION;
   PRAGMA EXCEPTION_INIT (NOT_ENOUGH_ROWS, -20000);
   
/******************************** INITIALIZE PROCEDURE *******************************/
   PROCEDURE initialize
   IS
   BEGIN
      -- Set scratch tablespace to USER default tablespace
      BEGIN
         SELECT default_tablespace INTO g_scratchtbs
            FROM DBA_USERS WHERE username = SYS_CONTEXT('USERENV', 'CURRENT_USER');
         -- In case that the default tablespace is SYSTEM/SYSAUX (package executed by SYS/SYSTEM), set it to database default tablespace
         IF g_scratchtbs = 'SYSTEM' OR g_scratchtbs = 'SYSAUX' THEN
            SELECT property_value INTO g_scratchtbs
               FROM DATABASE_PROPERTIES
                  WHERE property_name = 'DEFAULT_PERMANENT_TABLESPACE';
         END IF;
      EXCEPTION
         WHEN TABLE_OR_VIEW_DOES_NOT_EXIST THEN
            -- USERs default tablespace could not be determined, use database default tablespace
            SELECT property_value INTO g_scratchtbs
               FROM DATABASE_PROPERTIES
                  WHERE property_name = 'DEFAULT_PERMANENT_TABLESPACE';
      END;
   END initialize;

/************************** SCRATCH TABLESPACE ****************************************/
-- Scratch tablespace setter
   PROCEDURE SET_SCRATCH_TBS(p_tbs VARCHAR2)
   IS
      sContents   USER_TABLESPACES.CONTENTS%TYPE;
   BEGIN
      -- Check whether tablespace exists and that it is not UNDO or TEMPORARY
      SELECT MAX(contents) INTO sContents
         FROM USER_TABLESPACES WHERE tablespace_name = UPPER(p_tbs);
      IF sContents IS NULL THEN
         RAISE_APPLICATION_ERROR(-20004, 'Scratch tablespace does not exist!');
      ELSIF sContents = 'UNDO' OR sContents = 'TEMPORARY' THEN
         RAISE_APPLICATION_ERROR(-20005, 'Scratch tablespace is not permanent but ' || sContents || '!');
      END IF;
      g_scratchtbs := UPPER(p_tbs);
   END SET_SCRATCH_TBS;

-- Scratch tablespace getter
   FUNCTION GET_SCRATCH_TBS RETURN VARCHAR2
   IS
   BEGIN
      RETURN g_scratchtbs;
   END GET_SCRATCH_TBS;

/******************************* Compression type function ***************************/

   FUNCTION GET_COMPRESSION_TYPE_STR (p_nType NUMBER)
     RETURN VARCHAR2
     DETERMINISTIC
   IS
   BEGIN
      IF p_nType = "NOCOMPRESS" THEN
         RETURN 'NOCOMPRESS';
      ELSIF p_nType = OLTP THEN
         RETURN 'OLTP';
      ELSIF p_nType = HCC_QUERY_LOW THEN
         RETURN 'HCC Query Low';
      ELSIF p_nType = HCC_QUERY_HIGH THEN
         RETURN 'HCC Query High';
      ELSIF p_nType = HCC_ARCHIVE_LOW THEN
         RETURN 'HCC Archive Low';
      ELSIF p_nType =  HCC_ARCHIVE_HIGH THEN
         RETURN 'HCC Archive High';
      ELSIF p_nType = "ALL" THEN
         RETURN 'ALL';
      ELSE
         RETURN 'Unknown';
      END IF;
   END GET_COMPRESSION_TYPE_STR;

/******************************* VERBOSE routines ***************************/
   PROCEDURE VERBOSE (p_message VARCHAR2)
   IS
      l_nIndex   NUMBER;
   BEGIN
      l_nIndex := v_verbose_output.COUNT+1;
      v_verbose_output.EXTEND;
      v_verbose_output(l_nIndex).tms := SYSTIMESTAMP;
      v_verbose_output(l_nIndex).message := 'Verbose: ' || p_message;
   END VERBOSE;
   
   FUNCTION GET_VERBOSE RETURN verbose_output PIPELINED
   IS
   BEGIN
      -- No verbose output exists (nothing has been executed)
      IF v_verbose_output.COUNT = 0 THEN
         PIPE ROW(NULL);
         RETURN;
      END IF;
      
      -- Loop over stats and pipe them back
      FOR nIndex IN v_verbose_output.FIRST..v_verbose_output.LAST
      LOOP
         PIPE ROW (v_verbose_output(nIndex));
      END LOOP;
      RETURN;
   END;

/******************************* COMPRESSION SUB ROUTINES ****************************/

/****************************** TABLE COMPRESSION RATIOS ******************************/
   PROCEDURE CALC_COMP_RATIO_TABLE_SUB(p_owner VARCHAR2, p_table_name VARCHAR2, p_table_partition VARCHAR2, p_table_type VARCHAR2, p_type NUMBER)
   IS
      l_nIndex          NUMBER;
      l_sErrMsg         VARCHAR2(4000);
      l_nBytes          INTEGER;
   BEGIN
      verbose('Calling DBMS_COMPRESSION for ' || p_owner || '.' || p_table_name || '.' || p_table_partition || ' with compression type ' || GET_COMPRESSION_TYPE_STR(p_type));
      -- Calculate compression stats
      DBMS_COMPRESSION.GET_COMPRESSION_RATIO (g_scratchtbs, p_owner, p_table_name, p_table_partition, p_type, v_blkcnt_cmp, v_blkcnt_uncmp, v_row_cmp, v_row_uncmp, v_cmp_ratio, v_comptype_str);
      verbose('Storing results in collection');
      -- Extend collection index and collection
      l_nIndex := v_compression_stats.COUNT+1;
      v_compression_stats.EXTEND;
      -- Nocompress does not caluclate any numbers but sets all to 0!
      IF p_Type = "NOCOMPRESS" THEN
         SELECT blocks, blocks, ROUND(num_rows/blocks,0), ROUND(num_rows/blocks,0)
            INTO v_blkcnt_cmp, v_blkcnt_uncmp, v_row_cmp, v_row_uncmp
               FROM all_tables
                  WHERE owner = p_owner AND table_name = p_table_name;
         v_cmp_ratio := 1;
         v_comptype_str := '"No compression"';
      END IF;
      -- Set results into new collection
      v_compression_stats(l_nIndex).object_name := p_table_name;
      v_compression_stats(l_nIndex).subobject_name := p_table_partition;
      v_compression_stats(l_nIndex).object_type := p_table_type;
      v_compression_stats(l_nIndex).compression_type := GET_COMPRESSION_TYPE_STR(p_Type);
      v_compression_stats(l_nIndex).ratio := v_cmp_ratio;
      v_compression_stats(l_nIndex).blocks_comp := v_blkcnt_cmp;
      v_compression_stats(l_nIndex).blocks_uncomp := v_blkcnt_uncmp;
      v_compression_stats(l_nIndex).rows_comp := v_row_cmp;
      v_compression_stats(l_nIndex).rows_uncomp := v_row_uncmp;
      v_compression_stats(l_nIndex).comp_type_str := v_comptype_str;
      -- Calculate size after compression
      BEGIN
         verbose('Calculating bytes for object');
         SELECT bytes INTO l_nBytes
            FROM dba_segments
            WHERE owner = p_owner AND segment_name = p_table_name AND NVL(partition_name,' ') = NVL(p_table_partition,' ');
            v_compression_stats(l_nIndex).bytes := ROUND(l_nBytes / v_compression_stats(l_nIndex).ratio,0);
      EXCEPTION
         WHEN TABLE_OR_VIEW_DOES_NOT_EXIST THEN
            verbose('No access to DBA_SEGMENTS: -1');
            v_compression_stats(l_nIndex).bytes := -1;
         WHEN NO_DATA_FOUND THEN
            verbose('No segment exists for: ' || p_owner || '.' || p_table_name || '.' || p_table_partition);
            v_compression_stats(l_nIndex).bytes := -1;
            v_compression_stats(l_nIndex).comp_type_str := p_table_type || ' is empty: ' || p_owner || '.' || p_table_name || '.' || p_table_partition;
      END;
   EXCEPTION
      -- Not enough rows in table/partition to calculate HCC compression factors!
      -- There must be at least 1 Million rows in the table/partition to calculate compression factors!
      WHEN NOT_ENOUGH_ROWS THEN
         verbose('Not enough rows for compression calculation: ' || SQLERRM);
         l_nIndex := v_compression_stats.COUNT+1;
         v_compression_stats.extend;
         -- Set results into new compression
         v_compression_stats(l_nIndex).object_name := p_table_name;
         v_compression_stats(l_nIndex).subobject_name := p_table_partition;
         v_compression_stats(l_nIndex).object_type := p_table_type;
         v_compression_stats(l_nIndex).compression_type := GET_COMPRESSION_TYPE_STR(p_Type);
         l_sErrMsg := 'Not enough data in ';
         IF p_table_partition IS NULL THEN
            l_sErrMsg := l_sErrMsg || 'table ' || p_owner || '.' || p_table_name;
         ELSE
            l_sErrMsg := l_sErrMsg || 'table ' || p_owner || '.' || p_table_name || ' partition ' || p_table_partition;
         END IF;
            l_sErrMsg := l_sErrMsg || '! There must be at least 1,000,000 rows within the table/partition to calculate compression ratios!';
         v_compression_stats(l_nIndex).comp_type_str := l_sErrMsg;
   END CALC_COMP_RATIO_TABLE_SUB;

   PROCEDURE CALC_COMP_RATIO_TABLE(p_owner VARCHAR2, p_table_name VARCHAR2, p_table_partition VARCHAR2, p_object_type VARCHAR2, p_type NUMBER)
   IS
      -- l_sTableType VARCHAR2(18) := 'TABLE';
   BEGIN
      -- Get object type (Table, Table partition, Table subpartition)
      -- 2013-03-13 gvenzl: ObjectType gets passed on now
      /*
      IF p_table_partition IS NOT NULL THEN
         SELECT object_type INTO l_sTableType
            FROM all_objects 
               WHERE owner = p_owner
                  AND object_name = p_table_name AND subobject_name = p_table_partition;
         verbose('p_table_partition NOT NULL, partition type: ' || l_sTableType);
      END IF;
      */
      -- Calculate all compression options if ALL was specified
      IF p_type = "ALL" THEN
         verbose('Comp Type = ALL');
         CALC_COMP_RATIO_TABLE_SUB (p_owner, p_table_name, p_table_partition, p_object_type, "NOCOMPRESS");
         CALC_COMP_RATIO_TABLE_SUB (p_owner, p_table_name, p_table_partition, p_object_type, OLTP);
         CALC_COMP_RATIO_TABLE_SUB (p_owner, p_table_name, p_table_partition, p_object_type, HCC_QUERY_LOW);
         CALC_COMP_RATIO_TABLE_SUB (p_owner, p_table_name, p_table_partition, p_object_type, HCC_QUERY_HIGH);
         CALC_COMP_RATIO_TABLE_SUB (p_owner, p_table_name, p_table_partition, p_object_type, HCC_ARCHIVE_LOW);
         CALC_COMP_RATIO_TABLE_SUB (p_owner, p_table_name, p_table_partition, p_object_type, HCC_ARCHIVE_HIGH);
      -- Calculate specific compression option
      ELSE
         verbose('Comp Type = ' || p_type);
         CALC_COMP_RATIO_TABLE_SUB (p_owner, p_table_name, p_table_partition, p_object_type, p_type);
      END IF;
   END CALC_COMP_RATIO_TABLE;

/************************************** END TABLE COMPRESSION RATIOS ************************************************/

/****************************************** INDEX COMPRESSION RATIOS *************************************************/
   -- Index compression ratio sub routine (doing real calculation)
   PROCEDURE CALC_COMP_RATIO_INDEX_SUB(p_owner VARCHAR2, p_index_name VARCHAR2, p_type NUMBER)
   IS
      l_nIndex          NUMBER;
      l_sErrMsg         VARCHAR2(4000);
      l_nBytes          INTEGER;
   BEGIN
      --- NOT SUPPORTED ??? ---
      NULL;
   END CALC_COMP_RATIO_INDEX_SUB;
   
   -- Index compression ratio calculation
   PROCEDURE CALC_COMP_RATIO_INDEX(p_owner VARCHAR2, p_index_name VARCHAR2, p_type NUMBER)
   IS
   BEGIN
       -- Calculate all compression options if ALL was specified
       IF p_type = "ALL" THEN
          CALC_COMP_RATIO_INDEX_SUB (p_owner, p_index_name, "NOCOMPRESS");
          CALC_COMP_RATIO_INDEX_SUB (p_owner, p_index_name, OLTP);
          CALC_COMP_RATIO_INDEX_SUB (p_owner, p_index_name, HCC_QUERY_LOW);
          CALC_COMP_RATIO_INDEX_SUB (p_owner, p_index_name, HCC_QUERY_HIGH);
          CALC_COMP_RATIO_INDEX_SUB (p_owner, p_index_name, HCC_ARCHIVE_LOW);
          CALC_COMP_RATIO_INDEX_SUB (p_owner, p_index_name, HCC_ARCHIVE_HIGH);
       -- Calculate specific compression option
       ELSE
          CALC_COMP_RATIO_INDEX_SUB (p_owner, p_index_name, p_type);
      END IF;
   END CALC_COMP_RATIO_INDEX;

/************************************** END INDEX COMPRESSION RATIOS *************************************************/

/******************************* COMPRESSION RATIO CALCULATION PROCEDURES *******************************************/

   -- Schema level compression ratio aggregation
   PROCEDURE CALC_COMP_RATIO(p_owner VARCHAR2, p_type NUMBER DEFAULT "ALL")
   IS
      l_nIndex NUMBER;
   BEGIN
      -- Check if access to ALL_TABLES is given
      SELECT MAX(0) INTO l_nIndex FROM ALL_TABLES;
      -- Set schema analysis flag to TRUE
      b_SchemaAnalysis := TRUE;
      -- Clear collections
      v_compression_stats.DELETE;
      v_verbose_output.DELETE;
      -- Loop over all tables within the schema
      verbose('Schema analysis, loop over all tables for owner: ' || p_owner);
      verbose('Scratch tablespace: ' || GET_SCRATCH_TBS());
      FOR cur IN (SELECT table_name FROM all_tables WHERE owner = p_owner)
      LOOP
         verbose('Calculating compression for table: ' || p_owner || '.' || cur.table_name);
         CALC_COMP_RATIO(p_owner, cur.table_name, NULL, p_type);
      END LOOP;
      -- Set schema analysis flag back to FALSE again
      b_SchemaAnalysis := FALSE;
   EXCEPTION
      WHEN TABLE_OR_VIEW_DOES_NOT_EXIST THEN
         verbose('Schema analysis and no access to ALL_TABLES');
         l_nIndex := v_compression_stats.COUNT+1;
         v_compression_stats.extend;
         -- Set results into new compression
         v_compression_stats(l_nIndex).comp_type_str := 'The current user ' || SYS_CONTEXT('USERENV','CURRENT_USER') || ' has no read permissions on ALL_TABLES and can therefore not analyze the schema! GRANT SELECT ON ALL_TABLES TO the current user!';
   END CALC_COMP_RATIO;
  
   -- Object compression for specific compression level (default: ALL)
   PROCEDURE CALC_COMP_RATIO(p_owner VARCHAR2, p_object_name VARCHAR2, p_table_partition VARCHAR2 DEFAULT NULL, p_type NUMBER DEFAULT "ALL")
   IS
      l_sUserName         ALL_USERS.USERNAME%TYPE;
      l_sObjectType       ALL_OBJECTS.OBJECT_TYPE%TYPE;
   BEGIN
      -- Reset collection only if table is analyzed directly
      -- On schema level analysis the collection will be deleted before
      IF NOT b_SchemaAnalysis THEN
         v_compression_stats.DELETE;
         v_verbose_output.DELETE;
         verbose('Scratch tablespace: ' || GET_SCRATCH_TBS());
      END IF;
      -- Partition name is not null, object must be either a partition or subpartition
      IF p_table_partition IS NOT NULL THEN
         verbose('Table partition analysis');
         SELECT MAX(object_type) INTO l_sObjectType
           FROM all_objects
             WHERE owner = p_owner AND object_name = p_object_name AND subobject_name = p_table_partition;
         verbose('Table partition type: ' || l_sObjectType);
         -- Partition is a regular (not composite) partition, check whether subpartitions exist
         IF l_sObjectType = 'TABLE PARTITION' THEN
            -- If partition is actually a composite partition this SQL will retrieve all subpartitions and not the partition itself (due to AND subpartition_count = 0)
            -- If partition is a regular partition, the SQL will only retrieve the partition name again
            FOR cur IN
            (
               SELECT table_name, subpartition_name as partition_name, 'TABLE SUBPARTITION' as partition_type FROM all_tab_subpartitions WHERE table_owner = p_owner AND table_name = p_object_name AND partition_name = p_table_partition
               UNION ALL
               SELECT table_name, partition_name, 'TABLE PARTITION' as partition_type FROM all_tab_partitions WHERE table_owner = p_owner AND table_name = p_object_name AND partition_name = p_table_partition AND subpartition_count = 0
            )
            LOOP
               verbose('Automatic (sub)partition caluclation for ' || p_owner || '.' || cur.table_name || '.' || cur.partition_name);
               CALC_COMP_RATIO_TABLE(p_owner, cur.table_name, cur.partition_name, cur.partition_type, p_type);
            END LOOP;
         -- Partition is SUB-Partition (lowest level), start analyzing compression ratios
         ELSIF l_sObjectType = 'TABLE SUBPARTITION' THEN
            verbose('Analyzing subpartition compression statistics');
            CALC_COMP_RATIO_TABLE(p_owner, p_object_name, p_table_partition, l_sObjectType, p_type);
         END IF;
      -- Partition name is null, table based analysis
      ELSE
         verbose('Table analysis');
         -- Get object type of object to analyze
         -- MAX for table partitions, so that most sub type will be picked (TABLE, TABLE PARTITION, TABLE SUBPARTITION)
         SELECT MAX(object_type) INTO l_sObjectType
           FROM all_objects
             WHERE owner = p_owner AND object_name = p_object_name;
         verbose('Table type: ' || l_sObjectType);
         -- For specific object_type
         IF l_sObjectType LIKE 'TABLE%' OR l_sObjectType = 'MATERIALIZED VIEW' THEN
            -- If table but no specific partition was specified, run over all partitions and not just randomly over 1 million rows
            -- Usually partitioned tables are partitioned on specific patterns which will deliver different ratios
            -- By just randomly picking 1 million rows, the overall ratio will be meaningless!
            -- If table is not partition, execute compression advisor on table
            -- If table is not partitioned, all_tab_partitions will not return anything and all_tables will return table_name and NULL
            -- If table is partitioned, all_tab_partitions will return all partition names but all_tables not the table name itself due to "partitioned = 'NO'"!
            -- If table is sub partitioned, all_tab_partitions will not return anything due to "subpartition_count = 0", all_tables will also not return anything due to "partitioned = 'NO'"
            verbose('Looping over all potential table partitions');
            FOR cur IN
            (
               SELECT table_name, subpartition_name as partition_name FROM all_tab_subpartitions WHERE table_owner = p_owner AND table_name = p_object_name
               UNION ALL
               SELECT table_name, partition_name FROM all_tab_partitions WHERE table_owner = p_owner AND table_name = p_object_name AND subpartition_count = 0
               UNION ALL
               SELECT table_name, NULL FROM all_tables WHERE owner = p_owner AND table_name = p_object_name AND partitioned = 'NO'
            )
            LOOP
               verbose('Automatic table partition caluclation for ' || p_owner || '.' || cur.table_name || '.' || cur.partition_name);
               CALC_COMP_RATIO_TABLE(p_owner, cur.table_name, cur.partition_name, l_sObjectType, p_type);
            END LOOP;
         -- Table partitions are already handled at the beginning!
         -- ELSIF l_object_type = 'TABLE PARTITION' OR l_object_type = 'TABLE SUBPARTITION' THEN
         ELSIF l_sObjectType = 'LOB' THEN
            NULL;
         ELSIF l_sObjectType = 'INDEX' THEN
            NULL;
         ELSE
            SELECT MAX(username) INTO l_sUserName
               FROM all_users
                  WHERE username = p_owner;
            IF l_sUserName IS NULL THEN
               RAISE_APPLICATION_ERROR(-20001, 'Schema ' || p_owner || ' does not exist!');
            ELSE
               RAISE_APPLICATION_ERROR(-20002, 'No table with the name ' || p_object_name || ' does exist for schema ' || p_owner || '!');
            END IF;
         END IF;
      END IF;
   END CALC_COMP_RATIO;
   
/******************* COMPRESSION RESULTS FUNCTIONS *********************/
   -- Get compression ratio from previous calculation. Ratio only includes the object and the compression ratio/factor
   FUNCTION GET_COMP_RATIO RETURN compression_ratio PIPELINED
   IS
      l_ratio_record   compression_ratio_record;
   BEGIN
      -- If collection is empty it means the calculation hasn't been run yet. Abort and tell user to invoke CALC_COMP_RATIO routine first
      IF v_compression_stats.COUNT = 0 THEN
         RAISE_APPLICATION_ERROR(-20003,'Compression calculation has not been executed yet! Please run the CALC_COMP_RATIO routine first!');
      END IF;
      -- Loop through stats and return ratio records
      -- Records don't have constructors like collections, therefore each field needs to be assigned
      -- Each record must be piped as row, collection can't be returned as a whole as the PIPE ROW function builds it's own collection and the return result would then be a TABLE of a TABLE of the records!
      -- Btw: It's the 23th of February 2013 at 14:15 and I'm in the train on my way home in lovely, snowy Austria!
      FOR nIndex IN v_compression_stats.FIRST..v_compression_stats.LAST
      LOOP
         l_ratio_record.object_name       := v_compression_stats(nIndex).object_name;
         l_ratio_record.subobject_name    := v_compression_stats(nIndex).subobject_name;
         l_ratio_record.object_type       := v_compression_stats(nIndex).object_type;
         l_ratio_record.compression_type  := v_compression_stats(nIndex).compression_type;
         l_ratio_record.ratio             := v_compression_stats(nIndex).ratio;
         PIPE ROW (l_ratio_record);
      END LOOP;
      RETURN;
   END GET_COMP_RATIO;

/******************* COMPRESSION STATS FUNCTIONS *********************/
   -- Get all compression stats from previous calculation. Stats are all the values provided by DBMS_COMPRESSION
   FUNCTION GET_COMP_STATS RETURN compression_stats PIPELINED
   IS
   BEGIN
      -- If collection is empty it means the calculation hasn't been run yet. Abort and tell user to invoke CALC_COMP_RATIO routine first
      IF v_compression_stats.COUNT = 0 THEN
         RAISE_APPLICATION_ERROR(-20002,'Compression calculation has not been executed yet! Please run the CALC_COMP_RATIO routine first!');
      END IF;
      
      -- Loop over stats and pipe them back
      FOR nIndex IN v_compression_stats.FIRST..v_compression_stats.LAST
      LOOP
         PIPE ROW (v_compression_stats(nIndex));
      END LOOP;
      RETURN;
   END GET_COMP_STATS;
BEGIN
   initialize();
END COMPRESSION_ADVISOR;
/
show errors;