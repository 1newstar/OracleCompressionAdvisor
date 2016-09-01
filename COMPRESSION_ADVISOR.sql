------------------------------------------------------------------------------------------
---------------------------------- Compression Advisor -----------------------------------
-- Author: gvenzl (c) 2016 (v)1.0.1
-- This package provides an easy to use interface for Oracle Compression Advisor (DBMS_COMPRESSION)
-- It does not change any data or structure in any way nor does DBMS_COMPRESSION
-- However, to get an accurate estimate of the compression rates that could be achieved,
-- it has to be executed against production like data.
------------------------------------------------------------------------------------------

CREATE OR REPLACE PACKAGE COMPRESSION_ADVISOR
   AUTHID CURRENT_USER
IS
-- Compression types
   "NOCOMPRESS"         CONSTANT NUMBER := DBMS_COMPRESSION.COMP_NOCOMPRESS;
   OLTP                 CONSTANT NUMBER := DBMS_COMPRESSION.COMP_ADVANCED;
   HCC_QUERY_LOW        CONSTANT NUMBER := DBMS_COMPRESSION.COMP_QUERY_LOW;
   HCC_QUERY_HIGH       CONSTANT NUMBER := DBMS_COMPRESSION.COMP_QUERY_HIGH;
   HCC_ARCHIVE_LOW      CONSTANT NUMBER := DBMS_COMPRESSION.COMP_ARCHIVE_LOW;
   HCC_ARCHIVE_HIGH     CONSTANT NUMBER := DBMS_COMPRESSION.COMP_ARCHIVE_HIGH;
   "ALL"                CONSTANT NUMBER := OLTP + HCC_QUERY_LOW + HCC_QUERY_HIGH + HCC_ARCHIVE_LOW + HCC_ARCHIVE_HIGH;

   -- Scratch tablespace name
   g_scratchtbs         VARCHAR2(255);

   -- Collection for verbose output
   TYPE verbose_record IS RECORD ( tms TIMESTAMP, message VARCHAR2(32000) );
   TYPE verbose_output IS TABLE OF verbose_record;
   
   -- Record for compression ratio
   TYPE compression_ratio_record IS RECORD
   (
      object_name       VARCHAR2(4000),
      subobject_name    VARCHAR2(4000),
      object_type       VARCHAR2(255),
      compression_type  VARCHAR2(16),
      ratio             NUMBER
   );
   -- Collection for compression ratio
   TYPE compression_ratio IS TABLE OF compression_ratio_record;
   -- Record for compression stats
   TYPE compression_stats_record IS RECORD
   (
      object_name       VARCHAR2(4000),
      subobject_name    VARCHAR2(4000),
      object_type       VARCHAR2(4000),
      compression_type  VARCHAR2(16),
      ratio             NUMBER,
      bytes             INTEGER,
      blocks_comp       INTEGER,
      blocks_uncomp     INTEGER,
      rows_comp         INTEGER,
      rows_uncomp       INTEGER,
      comp_type_str     VARCHAR2(4000)
   );
   -- Collection for compression stats
   TYPE compression_stats IS TABLE OF compression_stats_record;
   
/******************** METHODS ***************************/
-- Scratch Tablespace setter and getter
   PROCEDURE SET_SCRATCH_TBS(p_tbs VARCHAR2);
   FUNCTION  GET_SCRATCH_TBS RETURN VARCHAR2;

-- Verbose output function
   FUNCTION GET_VERBOSE RETURN verbose_output PIPELINED;
   
/*** Compression ratio functions ***/
-- Calculate compression ratio (default: ALL) for schema
   PROCEDURE CALC_COMP_RATIO(p_owner VARCHAR2, p_type NUMBER DEFAULT "ALL");

-- Calculate compression ratio (default: ALL) for an object (Supported for: Table, Table partition, LOB, Index)
   PROCEDURE CALC_COMP_RATIO(p_owner VARCHAR2, p_object_name VARCHAR2, p_table_partition VARCHAR2 DEFAULT NULL, p_type NUMBER DEFAULT "ALL");
   
/*** Compression stats functions ***/
-- Schema for specific compression level (default: ALL)
   FUNCTION GET_COMP_RATIO RETURN compression_ratio PIPELINED;

-- Object compress for specific compression level (default: ALL)
   FUNCTION GET_COMP_STATS RETURN compression_stats PIPELINED;
   
END COMPRESSION_ADVISOR;
/
show errors;

CREATE OR REPLACE PUBLIC SYNONYM COMPRESSION_ADVISOR FOR COMPRESSION_ADVISOR;
GRANT EXECUTE ON COMPRESSION_ADVISOR TO PUBLIC;