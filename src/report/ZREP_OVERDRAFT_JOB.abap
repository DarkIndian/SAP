*&---------------------------------------------------------------------*
*& Report       : ZREP_OVERDRAFT_JOB
*& Description  : Overdraft Batch Job – Classical ABAP Report
*&
*& Complements ZCL_BATCH_OVERDRAFT_JOB (Application Job Framework).
*& Supports scheduling via SM36/SM37, SUBMIT, external schedulers,
*& internal ABAP API, and recurring jobs.
*&
*& Selection-screen event model
*& ─────────────────────────────
*& INITIALIZATION         : Pre-fill parameters from configuration table
*& AT SELECTION-SCREEN
*&   ON p_bparea          : Validate bank posting area exists
*&   ON p_limtype         : Validate limit type against domain values
*&   ON p_odsince         : Overdraft-since date must not be future
*&   ON p_keydt           : Key date must not precede overdraft-since
*& AT SELECTION-SCREEN    : Authorization check + cross-field rules
*& START-OF-SELECTION     : CDS call + spool output + Application Log
*&---------------------------------------------------------------------*
REPORT zrep_overdraft_job
  NO STANDARD PAGE HEADING
  LINE-SIZE 255.


*----------------------------------------------------------------------*
* TYPES
*----------------------------------------------------------------------*
TYPES:
  BEGIN OF ty_result,
    ext_acc_number    TYPE char35,
    iban              TYPE iban,
    region            TYPE regio,
    bank_key          TYPE bankk,
    bank_posting_area TYPE char10,
    product           TYPE char40,
    currency          TYPE waers,
    overdraft_amount  TYPE wertv8,
    overdraft_since   TYPE dats,
    limit_type        TYPE char10,
  END OF ty_result,

  tt_result TYPE STANDARD TABLE OF ty_result WITH DEFAULT KEY.


*----------------------------------------------------------------------*
* CONSTANTS
*----------------------------------------------------------------------*
CONSTANTS:
  gc_lim_nolimit  TYPE char10 VALUE 'NOLIMIT',
  gc_lim_external TYPE char10 VALUE 'EXTLIMIT',
  gc_lim_internal TYPE char10 VALUE 'INTLIMIT',
  gc_log_object   TYPE balobj_d  VALUE 'ZOVERDRAFT',
  gc_log_subobj   TYPE balsubobj VALUE 'BATCH',
  gc_config_key   TYPE char20 VALUE 'DEFAULT'.


*----------------------------------------------------------------------*
* DATA
*----------------------------------------------------------------------*
DATA:
  gt_result     TYPE tt_result,
  go_log        TYPE REF TO if_bali_log,
  gv_log_handle TYPE if_bali_log=>ty_handle,
  gv_iban_ref   TYPE iban,      "< reference field for SELECT-OPTIONS s_iban
  gv_prod_ref   TYPE char40.    "< reference field for SELECT-OPTIONS s_prod


*----------------------------------------------------------------------*
* SELECTION SCREEN
*----------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b_mand WITH FRAME TITLE TEXT-t01.

  PARAMETERS:
    p_odsince TYPE dats            OBLIGATORY,          "Overdraft Since Date
    p_keydt   TYPE dats            OBLIGATORY,          "Key Date
    p_bparea  TYPE char10          OBLIGATORY,          "Bank Posting Area
    p_limtype TYPE zde_limit_type  OBLIGATORY.          "Limit Type

  SELECTION-SCREEN SKIP.

  PARAMETERS:
    p_spool   RADIOBUTTON GROUP spl DEFAULT 'X',        "Write Spool
    p_nospool RADIOBUTTON GROUP spl.                    "No Spool Output

SELECTION-SCREEN END OF BLOCK b_mand.

SELECTION-SCREEN BEGIN OF BLOCK b_opt WITH FRAME TITLE TEXT-t02.

  PARAMETERS:
    p_extacc  TYPE char35,                              "External Account Number
    p_region  TYPE regio,                               "Region
    p_bankkey TYPE bankk,                               "Bank Key
    p_curr    TYPE waers,                               "Currency
    p_minovd  TYPE wertv8.                              "Minimum Overdraft

  SELECT-OPTIONS:
    s_iban  FOR gv_iban_ref  NO INTERVALS,              "IBAN
    s_prod  FOR gv_prod_ref.                            "Product(s)

SELECTION-SCREEN END OF BLOCK b_opt.


*----------------------------------------------------------------------*
* INITIALIZATION
* Pre-populate the selection screen with defaults from ZTOVERDRAFT_CONFIG.
* User values already stored in a variant take precedence because this
* event fires before the variant is applied in batch mode.
*----------------------------------------------------------------------*
INITIALIZATION.

  PERFORM fill_from_config_table.


*----------------------------------------------------------------------*
* AT SELECTION-SCREEN ON p_odsince
* Overdraft-since date must not be in the future.
*----------------------------------------------------------------------*
AT SELECTION-SCREEN ON p_odsince.

  IF p_odsince > sy-datum.
    MESSAGE e010(zoverdraft).   "Overdraft since date & must not be in the future
  ENDIF.


*----------------------------------------------------------------------*
* AT SELECTION-SCREEN ON p_keydt
* Key date must not precede the overdraft-since date.
*----------------------------------------------------------------------*
AT SELECTION-SCREEN ON p_keydt.

  IF p_odsince IS NOT INITIAL AND p_keydt < p_odsince.
    MESSAGE e011(zoverdraft).   "Key date & must not be before overdraft since date &
  ENDIF.


*----------------------------------------------------------------------*
* AT SELECTION-SCREEN ON p_bparea
* Verify that the bank posting area exists in the master data.
*----------------------------------------------------------------------*
AT SELECTION-SCREEN ON p_bparea.

  IF p_bparea IS NOT INITIAL.
    PERFORM validate_bank_posting_area.
  ENDIF.


*----------------------------------------------------------------------*
* AT SELECTION-SCREEN ON p_limtype
* Validate that the entered value belongs to domain ZDE_LIMIT_TYPE.
*----------------------------------------------------------------------*
AT SELECTION-SCREEN ON p_limtype.

  IF p_limtype IS NOT INITIAL.
    IF p_limtype <> gc_lim_nolimit  AND
       p_limtype <> gc_lim_external AND
       p_limtype <> gc_lim_internal.
      MESSAGE e012(zoverdraft) WITH p_limtype.  "Limit type & is invalid
    ENDIF.
  ENDIF.


*----------------------------------------------------------------------*
* AT SELECTION-SCREEN
* Fires on F8 (Execute) – last gate before START-OF-SELECTION.
*   1. Authorization check
*   2. Cross-field dependency rules
*----------------------------------------------------------------------*
AT SELECTION-SCREEN.

  "-- 1. Authorization check ----------------------------------------
  PERFORM check_authorization.

  "-- 2. Cross-field Rule I: Currency ↔ Minimum Overdraft -----------
  "       Either both must be filled or both must be empty.
  IF p_curr IS NOT INITIAL AND p_minovd IS INITIAL.
    MESSAGE e020(zoverdraft).   "Minimum overdraft amount is required when currency is specified
  ENDIF.

  IF p_minovd IS NOT INITIAL AND p_curr IS INITIAL.
    MESSAGE e021(zoverdraft).   "Currency is required when minimum overdraft amount is specified
  ENDIF.

  "-- 3. Cross-field Rule II: External Account, Region, Bank Key ----
  "       If any one is supplied then all three must be supplied.
  DATA(lv_grp_count) =
      COND i( WHEN p_extacc  IS NOT INITIAL THEN 1 ELSE 0 )
    + COND i( WHEN p_region  IS NOT INITIAL THEN 1 ELSE 0 )
    + COND i( WHEN p_bankkey IS NOT INITIAL THEN 1 ELSE 0 ).

  IF lv_grp_count > 0 AND lv_grp_count < 3.
    MESSAGE e022(zoverdraft).   "External account, region, and bank key must all be provided together
  ENDIF.


*----------------------------------------------------------------------*
* START-OF-SELECTION
* All validations have passed. Execute the job logic.
*----------------------------------------------------------------------*
START-OF-SELECTION.

  PERFORM initialize_applog.

  PERFORM write_log USING 'I' 'Overdraft batch job started'.

  PERFORM call_cds_view.

  IF p_spool = abap_true.
    PERFORM write_spool_output.
  ENDIF.

  PERFORM write_log USING 'I' 'Overdraft batch job completed'.

  PERFORM save_applog.


*&---------------------------------------------------------------------*
*& FORM fill_from_config_table
*& Reads ZTOVERDRAFT_CONFIG (key = DEFAULT) and applies each stored
*& default only when the corresponding parameter is still initial.
*& A value that the user has already entered is never overwritten.
*&---------------------------------------------------------------------*
FORM fill_from_config_table.

  SELECT SINGLE *
    FROM ztoverdraft_config
    WHERE mandt      = @sy-mandt
      AND config_key = @gc_config_key
    INTO @DATA(ls_config).

  CHECK sy-subrc = 0.

  IF p_odsince  IS INITIAL. p_odsince  = ls_config-overdraft_since.   ENDIF.
  IF p_keydt    IS INITIAL. p_keydt    = ls_config-key_date.           ENDIF.
  IF p_bparea   IS INITIAL. p_bparea   = ls_config-bank_posting_area.  ENDIF.
  IF p_limtype  IS INITIAL. p_limtype  = ls_config-limit_type.         ENDIF.
  IF p_extacc   IS INITIAL. p_extacc   = ls_config-ext_acc_number.     ENDIF.
  IF p_region   IS INITIAL. p_region   = ls_config-region.             ENDIF.
  IF p_bankkey  IS INITIAL. p_bankkey  = ls_config-bank_key.           ENDIF.
  IF p_curr     IS INITIAL. p_curr     = ls_config-currency.           ENDIF.
  IF p_minovd   IS INITIAL. p_minovd   = ls_config-min_overdraft.      ENDIF.

ENDFORM.


*&---------------------------------------------------------------------*
*& FORM validate_bank_posting_area
*& Existence check for the entered bank posting area.
*& Replace the SELECT with the appropriate BCA master data table/view.
*&---------------------------------------------------------------------*
FORM validate_bank_posting_area.

  SELECT SINGLE bank_posting_area
    FROM zbca_posting_area            "< replace with actual BCA table
    WHERE bank_posting_area = @p_bparea
    INTO @DATA(lv_bparea_check).      "#EC CI_SEL_NESTED

  IF sy-subrc <> 0.
    MESSAGE e013(zoverdraft) WITH p_bparea.  "Bank posting area & does not exist
  ENDIF.

ENDFORM.


*&---------------------------------------------------------------------*
*& FORM check_authorization
*& Checks authorization object Z_OD_JOB:
*&   ACTVT = 16 (Execute)  /  Z_BPAREA = bank posting area entered.
*& Issues a terminating error message if the check fails so the
*& selection screen is redisplayed and the job cannot proceed.
*&---------------------------------------------------------------------*
FORM check_authorization.

  AUTHORITY-CHECK OBJECT 'Z_OD_JOB'
    ID 'ACTVT'    FIELD '16'
    ID 'Z_BPAREA' FIELD p_bparea.

  IF sy-subrc <> 0.
    MESSAGE e001(zoverdraft) WITH sy-uname p_bparea.
    "You are not authorized to run this job for bank posting area &2 (User: &1)
  ENDIF.

ENDFORM.


*&---------------------------------------------------------------------*
*& FORM initialize_applog
*& Creates the Application Log header. Called once at the start of
*& START-OF-SELECTION so the handle is available to all subsequent
*& WRITE_LOG calls and is saved exactly once at the end.
*&---------------------------------------------------------------------*
FORM initialize_applog.

  TRY.
      go_log        = cl_bali_log=>create_with_header(
                          iv_object    = gc_log_object
                          iv_subobject = gc_log_subobj ).
      gv_log_handle = go_log->get_handle( ).
    CATCH cx_bali_runtime INTO DATA(lx_bali).
      WRITE: / 'Application log initialisation failed:', lx_bali->get_text( ).
  ENDTRY.

ENDFORM.


*&---------------------------------------------------------------------*
*& FORM write_log
*& Appends a free-text message to the open Application Log.
*&---------------------------------------------------------------------*
FORM write_log USING iv_msgty TYPE symsgty
                     iv_text  TYPE string.

  CHECK go_log IS BOUND.

  TRY.
      DATA(lo_msg) = cl_bali_free_text_msg=>create(
                         iv_severity = iv_msgty
                         iv_text     = iv_text ).
      go_log->add_item( io_item = lo_msg ).
    CATCH cx_bali_runtime.
      "Swallow silently – log failure must not abort the batch job
  ENDTRY.

ENDFORM.


*&---------------------------------------------------------------------*
*& FORM save_applog
*& Persists the Application Log to the database. Viewable via SLG1
*& using object ZOVERDRAFT / sub-object BATCH.
*&---------------------------------------------------------------------*
FORM save_applog.

  CHECK go_log IS BOUND.

  TRY.
      cl_bali_log_db=>get_instance( )->save_log( io_log = go_log ).
    CATCH cx_bali_runtime INTO DATA(lx_bali).
      WRITE: / 'Application log save failed:', lx_bali->get_text( ).
  ENDTRY.

ENDFORM.


*&---------------------------------------------------------------------*
*& FORM call_cds_view
*& Reads ZCDS_OVERDRAFT_ITEMS with the user's filter criteria.
*& Single-value optional parameters are converted to single-row
*& ranges so the WHERE clause remains uniform.
*& Logs a warning when no data is returned.
*&---------------------------------------------------------------------*
FORM call_cds_view.

  "-- Build ad-hoc ranges for single-value optional fields so the
  "   WHERE clause is symmetric regardless of whether they are filled.
  DATA lt_extacc  TYPE RANGE OF char35.
  DATA lt_region  TYPE RANGE OF regio.
  DATA lt_bankkey TYPE RANGE OF bankk.
  DATA lt_curr    TYPE RANGE OF waers.

  IF p_extacc  IS NOT INITIAL.
    lt_extacc  = VALUE #( ( sign = 'I' option = 'EQ' low = p_extacc  ) ).
  ENDIF.
  IF p_region  IS NOT INITIAL.
    lt_region  = VALUE #( ( sign = 'I' option = 'EQ' low = p_region  ) ).
  ENDIF.
  IF p_bankkey IS NOT INITIAL.
    lt_bankkey = VALUE #( ( sign = 'I' option = 'EQ' low = p_bankkey ) ).
  ENDIF.
  IF p_curr    IS NOT INITIAL.
    lt_curr    = VALUE #( ( sign = 'I' option = 'EQ' low = p_curr    ) ).
  ENDIF.

  SELECT FROM zcds_overdraft_items       "< replace with actual CDS view
    FIELDS ext_acc_number,
           iban,
           region,
           bank_key,
           bank_posting_area,
           product,
           currency,
           overdraft_amount,
           overdraft_since,
           limit_type
    WHERE overdraft_since    >= @p_odsince
      AND key_date           <= @p_keydt
      AND bank_posting_area   = @p_bparea
      AND limit_type          = @p_limtype
      AND ext_acc_number     IN @lt_extacc
      AND region             IN @lt_region
      AND bank_key           IN @lt_bankkey
      AND iban               IN @s_iban
      AND product            IN @s_prod
      AND currency           IN @lt_curr
      AND overdraft_amount   >= @p_minovd
    INTO TABLE @gt_result.

  IF gt_result IS INITIAL.
    PERFORM write_log USING 'W' 'CDS view returned no data for the given selection criteria'.
  ELSE.
    PERFORM write_log USING 'I'
      |CDS view returned { lines( gt_result ) } record(s)|.
  ENDIF.

ENDFORM.


*&---------------------------------------------------------------------*
*& FORM write_spool_output
*& Writes the result set to the job spool using ABAP List Processing.
*& Skips output silently when no data was returned by the CDS view.
*&---------------------------------------------------------------------*
FORM write_spool_output.

  IF gt_result IS INITIAL.
    PERFORM write_log USING 'W' 'No spool output generated – result set is empty'.
    RETURN.
  ENDIF.

  "-- Page header
  NEW-PAGE.
  WRITE: /  TEXT-h01,                         "OVERDRAFT BATCH JOB – OUTPUT
            (30) TEXT-h02, p_odsince,          "Overdraft Since :
         /  (30) TEXT-h03, p_keydt,            "Key Date        :
         /  (30) TEXT-h04, p_bparea,           "Bank Posting Area:
         /  (30) TEXT-h05, sy-datum,           "Generated On    :
                           sy-uzeit,
                           sy-uname.
  ULINE.

  "-- Column headings
  WRITE: /1(36)  TEXT-c01,                    "External Account Number
          37(21) TEXT-c02,                    "IBAN
          59(6)  TEXT-c03,                    "Region
          66(15) TEXT-c04,                    "Bank Key
          82(40) TEXT-c05,                    "Product
         123(5)  TEXT-c06,                    "Curr.
         129(20) TEXT-c07,                    "Overdraft Amount
         150(10) TEXT-c08,                    "Since
         161(10) TEXT-c09.                    "Limit Type
  ULINE.

  "-- Detail lines
  LOOP AT gt_result INTO DATA(ls_result).
    WRITE: /1(36)  ls_result-ext_acc_number,
            37(21) ls_result-iban,
            59(6)  ls_result-region,
            66(15) ls_result-bank_key,
            82(40) ls_result-product,
           123(5)  ls_result-currency,
           129(20) ls_result-overdraft_amount
                     CURRENCY ls_result-currency,
           150(10) ls_result-overdraft_since,
           161(10) ls_result-limit_type.
  ENDLOOP.

  ULINE.
  WRITE: / TEXT-f01, lines( gt_result ).      "Total records:

  PERFORM write_log USING 'S'
    |Spool output written – { lines( gt_result ) } record(s)|.

ENDFORM.
