# Oracle Compression Advisor
An easy to use interface for Oracle Compression Advisor (DBMS_COMPRESSION).  

## Prerequisites
### Database version

#### 11.1 and earlier
Compression Advisor doesn’t ship with the Oracle Database by default nor does COMPRESSION_ADVISOR support those versions yet. However, you can run Compression Advisor manually:

1. Download Compression Advisor from:
[http://www.oracle.com/technology/products/database/compression/compression-
advisor.html](http://www.oracle.com/technology/products/database/compression/compression-
advisor.html)
2. In SQL*Plus prompt run:  
`@prvtcomp.plb`  
`@dbmscomp.sql`
3. Follow the instructions in `readme.txt`

#### 11.2.0.1 and Linux x86
For Linux x86 ports, the Compression Advisor is available as a patch on top of 11.2.0.1.

Apply patch for Bug `8896202`  
Run the post install instructions mentioned in the readme.

	cd $ORACLE_HOME/rdbms/admin sqlplus / as sysdba
	SQL> @dbmscomp.sql
	SQL> @prvtcmpr.plb

For all other ports the Compression Advisor is included in the 11.2.0.2 release.

#### 11.2.0.2 and later
Compression Advisor is included in the release and no additional setup is required.

## Using Oracle Compression Advisor
### Overview
The COMPRESSION_ADVISOR package invokes Oracle Compression Advisor to gather compression-related information within a database environment.  The package provides an easy interface for calculating compression ratios and lets you query the results via SQL which on the other hand allows you to easily spool the data into a text or csv file for further use as well as just re-querying the data several times without running the Compression Advisor again.
 The package aims for an easy-to-use, off-you-go approach. To calculate any compression ratios, all you need is to invoke one procedure and then select the results from a table (pipelined) function.
 The package also lets you define the scratch tablespace to be used throughout your session.

>***Note:*** Oracle Compression Advisor needs a scratch tablespace where it can create intermediate compressed tables to analyze the compression ratios. The advisor takes a sample of (currently 1 million of HCC) rows and loads them into a compressed intermediate table to give you the best estimate possible. After it has done so it drops the intermediate table again. **Compression Advisor DOES NOT modify any structure or data within your database!** All it does is to create an intermediate table with the compression level you want to get advice on, copies a sample of (currently 1 million) rows into that table and analyzes the intermediate table afterwards. After that it drops that intermediate table again, bringing the database back to the state it was.

However, you don't have to define a scratch tablespace. If none is defined, it will use the users default tablespace via querying the `DEFAULT_TABLESPACE` column in the `DBA_USERS` view. If no permission to this view is given to the user executing the package, the package will use the database default tablespace by querying the `DEFAULT_PERMANENT_TABLESPACE` property in the `DATABASE_PROPERTIES` view. 

>***Note:*** If you execute the package as SYS or SYSTEM the `SYSTEM` tablespace would be the default tablespace. In this case Compression Advisor will use the database default tablespace!

Oracle Compression Advisor uses a fixed sample size of currently 1 million rows. If the table/ (sub-) partition does not have sufficient rows in it, it will be skipped! There are two reasons for this. The first is that compression only makes sense for big tables that accumulate a lot of storage space. A small table with e.g. 1000 rows does not accumulate enough storage so that compression would be beneficial.
The second reason is that compression ratios for a very small data set are meaningless as the compression ratios depend on the data itself and not the amount of rows. 1000 rows might compress very good or very bad depending on the data but 100 million rows might show the complete opposite picture.

### Approach
The package uses a recursive, you-want-it-all approach. This means:

#### Compression levels
If you don't specify an explicit compression level, the package will run with the `ALL` compression level calculating the ratios for all levels.  
Those levels are:

Level                  | Description
---------------------- | -----------
**`NONE`**             | Retrieve data as the table is right now (needs collected statistics on the object) 
**`ADVANCED`**         | Compression level for the Oracle Advanced Compression
**`HCC_QUERY_LOW`**    | Lowest Hybrid Columnar Compression (HCC) level
**`HCC_QUERY_HIGH`**   | Second Hybrid Columnar Compression (HCC) level
**`HCC_ARCHIVE_LOW`**  | Third Hybrid Columnar Compression (HCC) level
**`HCC_ARCHIVE_HIGH`** | Highest Hybrid Columnar Compression (HCC) level 
**`ALL`**              | All of the above compression levels including NONE
	
Oracle Database 12c and above provide additional levels:

Level            | Description
---------------- | -----------
**`ROW`**        | Row level compression
**`BASIC`**      | Compression level for Oracle basic compression
**`LOB_LOW`**    | SECUREFILE LOB compression – level LOW
**`LOB_MEDIUM`** | SECUREFILE LOB compression – level MEDIUM
**`LOB_HIGH`**   | SECUREFILE LOB compression – level HIGH

#### Recursive
The most granular object to calculate compression ratios on is a subpartition of a table. If you define a subpartition name the package will only calculate compression ratios on that one subpartition. If you define a partition name and that partition has no subpartitions, COMPRESSION_ADVISOR will calculate the compression ratios for all subpartitions. However, if the partition is standalone (with no subpartitions) it will calculate compression ratios for the partition itself. The same is true for tables. If a table is partitioned and you just specified the table name COMPRESSION_ADVISOR will run compression ratio calculations for all partitions and subpartitions if they exist, fully recursive.
COMPRESSION_ADVISOR takes it even a level higher up. If you just specify the schema name without any table the package will run compression ratio calculations on **ALL TABLES** including **ALL THE (SUB) PARTITIONS** of the schema! Depending how many tables, partitions and subpartitions the schema has and depending on how big they are, it can take a **very, very long time to calculate the ratios** for all of them!
It is therefore highly recommended to run Oracle Compression Advisor on table level and **not on schema level** unless you are very clear in what you're doing!

>**Note:** Compression Advisor will skip all tables/partitions that do not contain enough data for the sample size. This means that the amount of tables/partition is not as crucial as the amount of data.

## Security model
The COMPRESSION_ADVISOR package runs with the **current user’s privileges**. That means that whatever user executes COMPRESSION_ADVISOR also needs to have the appropriate privileges and not the user who defined the package. The reason for this is because COMPRESSION_ADVISOR creates actual compressed tables under the hood to give the most accurate compression ratio estimate. Because of this, COMPRESSION_ADVISOR needs some powerful privileges (see below) which should not be given to any ordinary user and also not passed on to users who just posses the EXECUTE privilege for COMPRESSION_ADVISOR.

The owner of the COMPRESSION_ADVISOR package needs the following privileges:

Privilege               | Object         | Object Type
----------------------- | -------------- | -------------
`CREATE PROCEDURE`      | `N/A`          | `N/A`
`CREATE PUBLIC SYNONYM` | `N/A`          | `N/A`
`SELECT`                | `DBA_SEGMENTS` | `SYSTEM VIEW`
`SELECT`                | `DBA_USERS`    | `SYSTEM VIEW`

The executing user needs the following privileges:


Privilege                     | Object            | Object Type
----------------------------- | ----------------- | -------------
`SELECT`                      | `DBA_SEGMENTS`    | `SYSTEM VIEW`
`SELECT`                      | `ALL_TAB_COLUMNS` | `SYSTEM VIEW`
`SELECT`                      | `DBA_USERS`       | `SYSTEM VIEW`
`SELECT`                      | `ALL_LOBS`        | `SYSTEM VIEW`
`SELECT`                      | `V_$PARAMETER`    | `SYSTEM DYNAMIC VIEW`
`ANALYZE ANY`                 | `N/A`             | `N/A`
`CREATE ANY TABLE`            | `N/A`             | `N/A`
`SELECT ANY TABLE`            | `N/A`             | `N/A`
`LOCK ANY TABLE`              | `N/A`             | `N/A`
`INSERT ANY TABLE`            | `N/A`             | `N/A`
`ALTER ANY TABLE`             | `N/A`             | `N/A`
`DROP ANY TABLE`              | `N/A`             | `N/A`
`QUOTA on scratch tablespace` | `Tablespace`      | `N/A`

## Constants
The COMPRESSION_ADVISOR package uses the constants shown below:

Constant           | TYPE     | Value                                   | Description
------------------ | -------- | --------------------------------------- | ------------------------ | ---------------------
`NONE`             | `NUMBER` | `DBMS_COMPRESSION.COMP_NOCOMPRESS`      | Gets current values from ALL_TABLES for the entire table (no analysis done, no sample size required) Table has to have valid statistics in order to give useful numbers!
`ADVANCED`         | `NUMBER` | `DBMS_COMPRESSION.COMP_ADVANCED`        | Runs advisor for Oracle Advanced Compression
`ROW`              | `NUMBER` | `DBMS_COMPRESSION.COMP_BLOCK`           | Runs advisor for row level compression
`BASIC`            | `NUMBER` | `DBMS_COMPRESSION.COMP_BASIC`           | Runs advisor for basic compression
`HCC_QUERY_LOW`    | `NUMBER` | `DBMS_COMPRESSION.COMP_QUERY_LOW`       | Runs advisor for Hybrid Columnar Compression level Query low
`HCC_QUERY_HIGH`   | `NUMBER` | `DBMS_COMPRESSION.COMP_QUERY_HIGH`      | Runs advisor for Hybrid Columnar Compression level Query high
`HCC_ARCHIVE_LOW`  | `NUMBER` | `DBMS_COMPRESSION.COMP_ARCHIVE_LOW`     | Runs advisor for Hybrid Columnar Compression level Archive low
`HCC_ARCHIVE_HIGH` | `NUMBER` | `DBMS_COMPRESSION.COMP_ARCHIVE_HIGH`    | Runs advisor for Hybrid Columnar Compression level Archive high
`LOB_LOW`          | `NUMBER` | `DBMS_COMPRESSION.COMP_LOB_LOW`         | Runs advisor for SECUREFILE compression – level LOW
`LOB_MEDIUM`       | `NUMBER` | `DBMS_COMPRESSION.COMP_LOB_MEDIUM`      | Runs advisor for SECUREFILE compression – level MEDIUM
`LOB_HIGH`         | `NUMBER` | `DBMS_COMPRESSION.COMP_LOB_HIGH`        | Runs advisor for SECUREFILE compression – level HIGH
`ALL`              | `NUMBER` | Sum of all the constant numbers above   | Runs advisor all the above compression options inclusive the NOCOMPRESS option

## Views
The COMPRESSION_ADVISOR package uses following views:

View                    | Usage
----------------------- | -----------------------------------------------------------------------
`ALL_OBJECTS`           | Used for object type determination (table, table partition, index, lob)
`ALL_TABLES`            | Used for NOCOMPRESS statistic 
`ALL_TAB_PARTITIONS`    | Used for automatic table partitions detection.
`ALL_TAB_SUBPARTITIONS` | Used for automatic table subpartitoins detection.
`ALL_EXTERNAL_TABLES`   | Used by DBMS_COMPRESSION
`ALL_TAB_COLS`          | Used by DBMS_COMPRESSION
`DBA_TAB_COLUMNS`       | Used by DBMS_COMPRESSION
`DATABASE_PROPERTIES`   | Used to determine the database default tablespace used as scratch tablespace. (Not needed if scratch tablespace will be set manually)
`USER_TABLESPACES`      | Used to determine the database default tablespace used as scratch tablespace. (Not needed if scratch tablespace will be set manually)
`DBA_SEGMENTS`          | Used for compressed size calculation of the segment. If not accessible, bytes will be -1.
`DBA_USERS`             | Used for user default tablespace lookup for default scratch tablespace. If not accessible, the database default tablespace will be considered. (Not needed if scratch tablespace will be set manually)     
`V_$PARAMETER`          | Used by DBMS_COMPRESSION     

## Error codes
The program may raise following errors:

### ORA-20001: "Schema <schema name> does not exist!"  
**Cause:**  
There could be no schema found with this name in ALL_USERS  
**Solution:**   
Verify that the schema name is correct and access to ALL_OBJECTS is given.

### ORA-20002: "No table with the name <table name> does exist for schema <schema name>!"  
**Cause:**  
There could be no table found with that name for the specified schema.  
**Solution:**  
Verify that the schema and the table names are correctly specified!

### ORA-20003: "Compression calculation has not been executed yet! Please run the CALC_COMP_RATIO routine first!"  
**Cause:**  
The user tried to retrieve the compression ratios or statistics without calculating them first.  
**Solution:**   
Before you query the compression ratios or statistics via GET_COMP_RATIO/GET_COMP_STATS you have to calculate them first by executing the CALC_COMP_RATIO procedure.

### ORA-20004: "Scratch tablespace does not exist!"  
**Cause:**  
The specified scratch tablespace does not exist in the database!  
**Solution:**  
Define a valid scratch tablespace name.

### ORA-20005: "Scratch tablespace is not permanent but <tablespace type>!"  
**Cause:**  
The specified scratch tablespace is either an UNDO or TEMPORARY tablespace!  
**Solution:**  
Specify a PERMANENT tablespace.

## Summary of COMPRESSION_ADVISOR Subprograms

Subprogram | Type | Description
---------- | ---- | ------------
SET_SCRATCH_TBS | Procedure | Sets the scratch tablespace to use for compression advisor to calculate the compression ratio.
GET_SCRATCH_TBS | Function | Returns the current scratch tablespace to use for compression advisor.
GET_VERBOSE | Function | Returns a collection with verbose output of the compression ratio calculations.
CALC_COMP_RATIO | Procedure | Calculates the compression ratios - needs to be executed before calling GET_COMP_RATIO.
GET_COMP_RATIO | Function | Returns a collection with the entire compression ratio calculated previously by CALC_COMP_RATIO.
GET_COMP_STATS | Function | Returns a collection with the entire compression statistics provided by DBMS_COMPRESSION, calculated previously by CALC_COMP_RATIO.

### SET_SCRATCH_TBS Procedure
This procedure sets the default scratch tablespace used by Compression Advisor to create a compressed subset of the data. If this procedure is not invoked, Compression Advisor will use the users default tablespace if retrievable (select grant on DBA_USERS is needed for this) or otherwise use the databases default tablespace.

**Syntax:**  
```
COMPRESSION_ADVISOR.SET_SCRATCH_TBS (
    p_ tbs    IN     VARCHAR2);
```
**Parameters:**
```
p_tbs            Name of the scratch tablespace to use
```

**Usage notes:**  
This procedure just sets an internal variable in the COMPRESSION_ADVISOR package and does not do any types of calculations or modifications.

### GET_SCRATCH_TBS Function
This function returns the current scratch tablespace used by COMPRESSION_ADVISOR.

**Syntax:**
```
COMPRESSION_ADVISOR.GET_SCRATCH_TBS ();
```
**Return Values:**
```
Name of the currently used scratch tablespace
```

### GET_VERBOSE Function
This function returns the verbose output of the compression ratio calculations.
GET_VERBOSE is a table function and is always used in the context of a SELECT statement.

**Syntax:**
```
SELECT ... FROM TABLE(COMPRESSION_ADVISOR.GET_VERBOSE());
```
**Return Values:**
```
GET_VERBOSE returns a table collection with following columns:
tms             TIMESTAMP      The timestamp of when the message was logged.
message     VARCHAR2       The log message.
```

### CALC_COMP_RATIO Procedure
 This procedure runs the actual compression ratio and statistics calculations for a schema, table or table partition.
The overload takes a table name and an optional partition name as IN arguments.
The schema based calculation will retrieve all tables and table partitions of the schema and calculate the compression levels on all of them. **Depending on the size of the schema this can take very long time and consume a lot of resources.
It is therefore recommended to run the overload and analyze the compression ratios per table or table partition.**  

In case that a table is partitioned but no partition name is passed, the procedure will calculate the compression ratios for all partitions fully recursive. 

**Syntax:**  
```
COMPRESSION_ADVISOR.CALC_COMP_RATIO (
         p_owner            IN  VARCHAR2,
         p_type             IN  NUMBER  DEFAULT "ALL");
COMPRESSION_ADVISOR.CALC_COMP_RATIO (
         p_owner            IN  VARCHAR2,
         p_object_name      IN  VARCHAR2,
         p_table_partition  IN  VARCHAR2,
         p_type             IN  NUMBER  DEFAULT "ALL");
```
**Parameters:**
```
p_owner             The schema/owner name of the table(s)/partition(s) to be analyzed
p_object_name       The name of the table name to analyze
p_table_partition   The table partition name to analyze
p_type              The compression type of which analysis should be performed – see COMPRESSION_ADVISOR Constants
```
**Usage notes:**
The procedure creates different tables in the scratch tablespace and runs analysis on these objects. It does not modify anything in the user-specified tables.

### GET_COMP_RATIO Function
This function returns the previously calculated compression ratios. Before this function is called CALC_COMP_RATIO has to be executed first otherwise this function will raise error ORA-2003.  

**Syntax:**
```
SELECT ... FROM TABLE(COMPRESSION_ADVISOR.GET_COMP_RATIO())';
```
**Return Values:**  
GET_COMP_RATIO returns a table collection with following columns:
```
object_name         VARCHAR2    The table name that has been analyzed
subobject_name      VARCHAR2    The partition name that has been analyzed in case the table is partitioned
object_type         VARCHAR2    The type of table/partition
compression_type    VARCHAR2    The calculated compression type - see COMPRESSION_ADVISOR Constants
ratio               NUMBER      The compression ratio, i.e. how many times would the table/partition be compressed with that compression type
```

### GET_COMP_STATS Function
This function returns the previously calculated compression statistics. Just as with GET_COMP_RATIO this function requires to run CALC_COMP_RATIO first otherwise this function will also raise error ORA-20003.  
This function is similar to GET_COMP_RATIO with the difference that this function returns all Compression Advisor statistics (see below Return Values) while GET_COMP_RATIO only returns the compression ratio itself for a given table/partition and compression type.  

**Syntax:**  
```
SELECT ... FROM TABLE(COMPRESSION_ADVISOR.GET_COMP_STATS());
```

**Return Values:**  
GET_COMP_STATS returns a table collection with following columns:  
```
object_name         VARCHAR2     The table name that has been analyzed
subobject_name      VARCHAR2     The partition name that has been analyzed in case the table is partitioned
object_type         VARCHAR2     The type of table/partition
compression_type    VARCHAR2     The calculated compression type – see COMPRESSION_ADVISOR Constants
ratio               NUMBER        The compression ratio, i.e. how many times would the table/partition be compressed with that compression type
sample_size         INTEGER        The amount of rows sampled for calculating the compression ratio
bytes               INTEGER        The amount of bytes the table/partition would occupy with that compression type
blocks_comp         INTEGER         The number of blocks needed to hold the sample size in compressed form
blocks_uncomp       INTEGER         The number of blocks needed to hold the sample size in uncompressed form
rows_comp           INTEGER         The amount of rows that fit into one block of the table in compressed form
rows_uncomp         INTEGER        The amount of rows that fit into one block of the table in uncompressed form
comp_type_str       VARCHAR2    The compression type string; holds a string rather than  just the type itself as well as potential errors encountered during the analysis
```

## Usage
The COMPRESSION_ADVISOR package aims for an easy-to-use, ready-to-go approach. To get compression ratios all that is needs is to execute following two methods:  
1. CALC_COMP_RATIO
2. GET_COMP_RATIO

To get a more sophisticated analysis of compression rates, the package provides a more sophisticated method:
1.	GET_COMP_STATS

The package also allows you to specify the needed scratch tablespace, if not set it will use the users default tablespace and if that cannot be retrieved due to whatever reason, it will use the database default tablespace. The method to specify the scratch tablespace is:
1.	SET_SCRATCH_TBS

The simplest way to get compression ratios for a table is:
```
BEGIN COMPRESSION_ADVISOR.CALC_COMP_RATIO(<USER>, <TABLENAME>); END;
SELECT * FROM TABLE(COMPRESSION_ADVISOR.GET_COMP_RATIO());
```
### Examples
#### Retrieve ADVANCED compression ratio for a single table
    
1. Set scratch tablespace to non-default tablespace COMP_SCRATCH
```
BEGIN COMPRESSION_ADVISOR.SET_SCRATCH_TBS('COMP_SCRATCH'); END;
```
2. Calculate compression ratio
```
BEGIN COMPRESSION_ADVISOR.CALC_COMP_RATIO(<USER>, <TABLE NAME>, <PARTITION NAME>, <COMPRESSION TYPE>); END;
BEGIN COMPRESSION_ADVISOR.CALC_COMP_RATIO('GVENZL', 'MYTABLE', NULL, COMPRESSION_ADVISOR.ADVANCED); END;
```
**First argument:**     The owner of the table → GVENZL  
**Second argument:**    The table name → MYTABLE  
**Third argument:**     The partition name of the table → NULL because the table isn't partitioned.  
**Fourth argument:**    The compression type to analyze → COMPRESSION_ADVISOR.ADVANCED as ADVANCED compression ratio is wanted.
3.	Retrieve compression ratio
```
SELECT * FROM TABLE(COMPRESSION_ADVISOR.GET_COMP_RATIO());
```
**Result:**  
OBJECT_NAME | SUBOBJECT_NAME | OBJECT_TYPE | COMPRESSION_TYPE | RATIO
----------- | -------------- | ----------- | ---------------- | -----
MYTABLE | (null) | TABLE | ADVANCED | 1

OBJECT_NAME         → The table name  
SUBOBJECT_NAME      → The partition name, null in this case  
OBJECT_TYPE         → The object_type, either TABLE, TABLE PARTITION or TABLE SUBPARTITION  
COMPRESSION_TYPE    → The calculated compression type  
RATIO               → The ratio that the table would compress with that compression type  

#### Retrieve HCC Query Low compression statistics for a single table partition

1.	Calculate compression ratio for table partition (scratch tablespace not set, therefore using default tablespace)
```
BEGIN COMPRESSION_ADVISOR.CALC_COMP_RATIO(<USER>, <TABLE NAME>, <PARTITION NAME>, <COMPRESSION TYPE>); END;
BEGIN COMPRESSION_ADVISOR.CALC_COMP_RATIO('GVENZL', 'MYPARTITIONEDTABLE', 'P1', COMPRESSION_ADVISOR.HCC_QUERY_LOW); END;
```
**First argument:** The owner of the table              → GVENZL  
**Second argument:** The table name                     → MYTABLE  
**Third argument:** The partition name of the table     → Partition P1  
**Fourth argument:** The compression type to analyze    → COMPRESSION_ADVISOR.HCC_QUERY_LOW as HCC Query Low compression ratio is wanted.
2.	Get compression statistics
```
SELECT * FROM TABLE(COMPRESSION_ADVISOR.GET_COMP_STATS());
```
**Results:**  
OBJECT_NAME | SUBOBJECT_NAME | OBJECT_TYPE | COMPRESSION_TYPE | RATIO | BYTES | BLOCKS_COMP | BLOCKS_UNCOMP | ROWS_COMP | ROWS_UNCOMP | COMP_TYPE_STR
----------- | ------------- | ------------ | ---------------- | ------ | ----- | ---------- | ------------- | --------- | ----- | -------
MYPARTITIONEDTABLE | P1 | TABLE PARTITION | HCC Query Low | 16.2 | 9320676 | 1100 | 17856 | 909 | 56 | Compress For Query Low

#### Retrieve ALL compression statistics for all table (sub) partitions
1.	Define scratch tablespace
```
BEGIN COMPRESSION_ADVISOR.SET_SCRATCH_TBS('COMP_SCRATCH'); END;
```
2.	Calculate compression ratio for table partitions recursively (scratch tablespace not set, therefore using default tablespace)
```
BEGIN COMPRESSION_ADVISOR.CALC_COMP_RATIO(<USER>, <TABLE NAME>); END;
BEGIN COMPRESSION_ADVISOR.CALC_COMP_RATIO('GVENZL','FIN_INVST_HISTORY_P_T'); END;
```
**First argument:** The owner of the table and its partitions   →   GVENZL  
**Second argument:** The table name                             →   FIN_INVST_HISTORY_P_T  
3.	Get compression ratio
```
SELECT * FROM TABLE(COMPRESSION_ADVISOR.GET_COMP_RATIO());
```

**Results:**
OBJECT_NAME | SUBOBJECT_NAME | OBJECT_TYPE | COMPRESSION_TYPE | RATIO | BYTES | BLOCKS COMP | BLOCKS UNCOMP | ROWS COMP | ROWS UNCOMP | COMP_TYPE_STR
----------- | -------------- | ----------- | ---------------- | ----- | ----- | ----------- | ------------- | --------- | ----------- | -------------
FIN_INVST_HISTORY_P_T | SYS_SUBP81 | TABLE SUBPARTITION | NOCOMPRESS | 1 | 301989888 | 147556 | 147556 | 68 | 68 | No compression
FIN_INVST_HISTORY_P_T | SYS_SUBP81 | TABLE SUBPARTITION | ADVANCED | 3.1 | 97416093 | 500 | 1555 | 210 | 67 | Compress For ADVANCED
FIN_INVST_HISTORY_P_T | SYS_SUBP81 | TABLE SUBPARTITION | HCC Query Low | 4.9 | 61630589 | 3003 | 14897 | 333 | 67 | Compress For Query Low
FIN_INVST_HISTORY_P_T | SYS_SUBP81 | TABLE SUBPARTITION | HCC Query High | 15.9 | 18993075 | 936 | 14897 | 1068 | 67 | Compress For Query High
FIN_INVST_HISTORY_P_T | SYS_SUBP81 | TABLE SUBPARTITION | HCC Archive Low | 17.2 | 17557552 | 864 | 14897 | 1157 | 67 | Compress For Archive Low
FIN_INVST_HISTORY_P_T | SYS_SUBP81 | TABLE SUBPARTITION | HCC Archive High | 26.2 | 11526332 | 568 | 14897 | 1761 | 67 | Compress For Archive High
FIN_INVST_HISTORY_P_T | SYS_SUBP82 | TABLE SUBPARTITION | NOCOMPRESS | 1 | 301989888 | 147556 | 147556 | 68 | 68 | No compression
FIN_INVST_HISTORY_P_T | SYS_SUBP82 | TABLE SUBPARTITION | ADVANCED | 3.1 | 97416093 | 635 | 1978 | 210 | 67 | Compress For ADVANCED
FIN_INVST_HISTORY_P_T | SYS_SUBP82 | TABLE SUBPARTITION | HCC Query Low | 4.9 | 61630589 | 3002 | 14896 | 333 | 67 | Compress For Query Low
FIN_INVST_HISTORY_P_T | SYS_SUBP82 | TABLE SUBPARTITION | HCC Query High | 15.9 | 18993075 | 936 | 14896 | 1068 | 67 | Compress For Query High
FIN_INVST_HISTORY_P_T | SYS_SUBP82 | TABLE SUBPARTITION | HCC Archive Low | 17.2 | 17557552 | 865 | 14896 | 1156 | 67 | Compress For Archive Low
FIN_INVST_HISTORY_P_T | SYS_SUBP82 | TABLE SUBPARTITION | HCC Archive High | 26.2 | 11526332 | 568 | 14896 | 1761 | 67 | Compress For Archive High
FIN_INVST_HISTORY_P_T | SYS_SUBP83 | TABLE SUBPARTITION | NOCOMPRESS | 1 | 310378496 | 147556 | 147556 | 68 | 68 | No compression
FIN_INVST_HISTORY_P_T | SYS_SUBP83 | TABLE SUBPARTITION | ADVANCED | 3.1 | 100122095 | 542 | 1684 | 210 | 67 | Compress For ADVANCED
FIN_INVST_HISTORY_P_T | SYS_SUBP83 | TABLE SUBPARTITION | HCC Query Low | 4.9 | 63342550 | 3004 | 14896 | 333 | 67 | Compress For Query Low
FIN_INVST_HISTORY_P_T | SYS_SUBP83 | TABLE SUBPARTITION | HCC Query High | 16.2 | 19159166 | 914 | 14896 | 1094 | 67 | Compress For Query High
FIN_INVST_HISTORY_P_T | SYS_SUBP83 | TABLE SUBPARTITION | HCC Archive Low | 17.2 | 18045261 | 866 | 14896 | 1155 | 67 | Compress For Archive Low
FIN_INVST_HISTORY_P_T | SYS_SUBP83 | TABLE SUBPARTITION | HCC Archive High | 26.4 | 11756761 | 563 | 14896 | 1776 | 67 | Compress For Archive High
FIN_INVST_HISTORY_P_T | SYS_SUBP84 | TABLE SUBPARTITION | NOCOMPRESS | 1 | 301989888 | 147556 | 147556 | 68 | 68 | No compression
FIN_INVST_HISTORY_P_T | SYS_SUBP84 | TABLE SUBPARTITION | ADVANCED | 3.1 | 97416093 | 667 | 2073 | 209 | 67 | Compress For ADVANCED
FIN_INVST_HISTORY_P_T | SYS_SUBP84 | TABLE SUBPARTITION | HCC Query Low | 4.9 | 61630589 | 3006 | 14895 | 333 | 67 | Compress For Query Low
FIN_INVST_HISTORY_P_T | SYS_SUBP84 | TABLE SUBPARTITION | HCC Query High | 15.9 | 18993075 | 936 | 14895 | 1068 | 67 | Compress For Query High
FIN_INVST_HISTORY_P_T | SYS_SUBP84 | TABLE SUBPARTITION | HCC Archive Low | 17.2 | 17557552 | 864 | 14895 | 1157 | 67 | Compress For Archive Low
FIN_INVST_HISTORY_P_T | SYS_SUBP84 | TABLE SUBPARTITION | HCC Archive High | 26.3 | 11482505 | 565 | 14895 | 1770 | 67 | Compress For Archive High

#### Get current scratch tablespace
1.	Retrieve current scratch tablespace
```
SELECT COMPRESSION_ADVISOR.GET_SCRATCH_TBS() FROM DUAL;
```
**Results:**  
```
COMPRESSION_ADVISOR.GET_SCRATCH_TBS()
COMP_SCRATCH
```

## Changes & Bug fixes
### v1.0.1
* Use database default permanent tablespace if user tablespace is SYTEM or SYSAUX (e.g. when executed as SYS)
* SET_SCRATCH_TBS: Check whether the passed scratch tablespace exists and is not UNDO or TEMPORARY
### v1.1.0
* Support for Oracle Database 12c
* Support for Oracle SECUREFILE LOB compression in 12c
* Implicit LOB compression ratio calculation from table compression
* Renaming of “NOCOMPRESSION” type to “NONE”
* Renaming of “OLTP” type to “ADVANCED”
