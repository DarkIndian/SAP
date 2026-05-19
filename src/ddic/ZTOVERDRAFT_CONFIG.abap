*&---------------------------------------------------------------------*
*& Dictionary Object: Configuration Table ZTOVERDRAFT_CONFIG
*& Purpose : Holds default parameter values for the overdraft batch job.
*&           If the user leaves a parameter blank in the job template,
*&           the job fills it from this table.
*&---------------------------------------------------------------------*
*
* TABLE DEFINITION (create in SE11 / Data Dictionary):
*
*   Table name   : ZTOVERDRAFT_CONFIG
*   Short text   : Overdraft Batch Job – Default Configuration
*   Delivery cls : C  (Customising, not transport-relevant by default)
*   Data class   : APPL1
*
*   Fields:
*   ┌──────────────────────┬──────────────┬────────────────────────────────────────────┐
*   │ Field                │ Type/Domain  │ Description                                │
*   ├──────────────────────┼──────────────┼────────────────────────────────────────────┤
*   │ MANDT (key)          │ MANDT        │ Client                                     │
*   │ CONFIG_KEY (key)     │ CHAR20       │ Configuration key (use 'DEFAULT')          │
*   │ OVERDRAFT_SINCE      │ DATS         │ Default overdraft-since date               │
*   │ KEY_DATE             │ DATS         │ Default key date                           │
*   │ BANK_POSTING_AREA    │ CHAR10       │ Default bank posting area                  │
*   │ LIMIT_TYPE           │ ZDE_LIMIT_TYPE│ Default limit type                       │
*   │ EXT_ACC_NUMBER       │ CHAR35       │ Default external account number            │
*   │ REGION               │ REGIO        │ Default region                             │
*   │ BANK_KEY             │ BANKK        │ Default bank key                           │
*   │ CURRENCY             │ WAERS        │ Default currency                           │
*   │ MIN_OVERDRAFT        │ WERTV8       │ Default minimum overdraft amount           │
*   └──────────────────────┴──────────────┴────────────────────────────────────────────┘
*
* NOTE: IBAN and Product lists are multi-value; store them in a
*       separate detail table ZTOVERDRAFT_CONFIG_D if needed.
*
*-----------------------------------------------------------------------
* DOMAIN: ZDE_LIMIT_TYPE
*   Data type : CHAR
*   Length    : 10
*   Fixed values:
*     NOLIMIT  – No Limit
*     EXTLIMIT – External Limit
*     INTLIMIT – Internal Limit
*
*-----------------------------------------------------------------------
* AUTHORIZATION OBJECT: Z_OD_JOB
*   Field 1: ACTVT  (Activity) – maintain value '16' (Execute)
*   Field 2: Z_BPAREA (Bank Posting Area) – restrict by area if needed
*-----------------------------------------------------------------------
