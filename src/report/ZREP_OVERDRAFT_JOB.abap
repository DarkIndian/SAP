*&---------------------------------------------------------------------*
*& Report      : ZREP_OVERDRAFT_JOB
*& Description : Classical ABAP report for the Overdraft Batch Job.
*&
*&   Complements ZCL_BATCH_OVERDRAFT_JOB (AJF class) so that the same
*&   job can be scheduled via SM36/SM37, called by SUBMIT, or run
*&   interactively.  Shares the same authorization object, config table,
*&   and Application Log object as the AJF class.
*&
*&   Schedule modes supported:
*&     • SM36 / SM37  (classical background job)
*&     • SUBMIT … AND RETURN  (called from another program)
*&     • JOB_SUBMIT API  (external / internal scheduler API)
*&     • Recurring job via SM36 periodic scheduling
*&---------------------------------------------------------------------*
REPORT zrep_overdraft_job.


*----------------------------------------------------------------------*
* Selection screen
*----------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b_mand WITH FRAME TITLE TEXT-t01.

  "-- Mandatory parameters
  PARAMETERS:
    p_odsince TYPE dats OBLIGATORY,          " Overdraft Since Date
    p_keydt   TYPE dats OBLIGATORY,          " Key Date
    p_bparea  TYPE char10 OBLIGATORY,        " Bank Posting Area
    p_spool   RADIOBUTTON GROUP spl          " Spool output
              DEFAULT 'X',
    p_nospool RADIOBUTTON GROUP spl,         " No spool output
    p_limtype TYPE char10 OBLIGATORY.        " Limit Type (domain ZDE_LIMIT_TYPE)

SELECTION-SCREEN END OF BLOCK b_mand.

SELECTION-SCREEN BEGIN OF BLOCK b_opt WITH FRAME TITLE TEXT-t02.

  "-- Optional single-value parameters
  PARAMETERS:
    p_extacc  TYPE char35,                   " External Account Number
    p_region  TYPE regio,                    " Region
    p_bankkey TYPE bankk,                    " Bank Key
    p_curr    TYPE waers,                    " Currency
    p_minovd  TYPE wertv8.                   " Minimum Overdraft

  "-- Optional multi-value parameters (select-options / table types)
  SELECT-OPTIONS:
    s_iban    FOR ('IBAN'),                  " IBAN list
    s_prod    FOR ('CHAR40').                " Product(s) list

SELECTION-SCREEN END OF BLOCK b_opt.


*----------------------------------------------------------------------*
* Global types
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
* Global data
*----------------------------------------------------------------------*
DATA: gt_result     TYPE tt_result,
      gv_log_handle TYPE if_bali_log=>ty_handle,
      go_log        TYPE REF TO if_bali_log.


*----------------------------------------------------------------------*
* INITIALIZATION – set default values from configuration table
*----------------------------------------------------------------------*
INITIALIZATION.
  PERFORM fill_from_config.


*----------------------------------------------------------------------*
* START-OF-SELECTION
*----------------------------------------------------------------------*
START-OF-SELECTION.

  "-- Initialise Application Log
  go_log = cl_bali_log=>create_with_header(
               iv_object    = 'ZOVERDRAFT'
               iv_subobject = 'BATCH' ).
  gv_log_handle = go_log->get_handle( ).

  PERFORM log_message USING 'I' 'Overdraft batch job (report) started.'.

  "-- Authorization check
  PERFORM check_authorization.

  "-- Cross-dependency validation
  PERFORM validate_cross_dependencies.

  "-- Call CDS view
  PERFORM call_cds_view.

  "-- Write spool output
  IF p_spool = 'X'.
    PERFORM write_spool_output.
  ENDIF.

  PERFORM log_message USING 'I' 'Overdraft batch job (report) completed.'.

  "-- Save Application Log
  cl_bali_log_db=>get_instance( )->save_log( io_log = go_log ).


*----------------------------------------------------------------------*
* FORM fill_from_config
*----------------------------------------------------------------------*
FORM fill_from_config.

  SELECT SINGLE *
    FROM ztoverdraft_config
    WHERE mandt      = @sy-mandt
      AND config_key = @'DEFAULT'
    INTO @DATA(ls_config).

  IF sy-subrc <> 0.
    RETURN.
  ENDIF.

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


*----------------------------------------------------------------------*
* FORM check_authorization
*----------------------------------------------------------------------*
FORM check_authorization.

  AUTHORITY-CHECK OBJECT 'Z_OD_JOB'
    ID 'ACTVT'    FIELD '16'
    ID 'Z_BPAREA' FIELD p_bparea.

  IF sy-subrc <> 0.
    PERFORM log_message USING 'E'
      |User { sy-uname } not authorised for bank posting area { p_bparea }.|.
    cl_bali_log_db=>get_instance( )->save_log( io_log = go_log ).
    MESSAGE e001(zoverdraft) WITH sy-uname p_bparea.
    STOP.
  ENDIF.

  PERFORM log_message USING 'I' 'Authorization check passed.'.

ENDFORM.


*----------------------------------------------------------------------*
* FORM validate_cross_dependencies
*----------------------------------------------------------------------*
FORM validate_cross_dependencies.

  DATA lv_error TYPE abap_bool VALUE abap_false.

  "-- Rule I: Currency ↔ Minimum Overdraft
  IF ( p_curr   IS NOT INITIAL AND p_minovd IS INITIAL ) OR
     ( p_curr   IS INITIAL     AND p_minovd IS NOT INITIAL ).
    PERFORM log_message USING 'E'
      'Currency and Minimum Overdraft must both be filled or both be empty.'.
    lv_error = abap_true.
  ENDIF.

  "-- Rule II: Ext Acc Number, Region, Bank Key – all three or none
  DATA(lv_cnt) = COND i( WHEN p_extacc  IS NOT INITIAL THEN 1 ELSE 0 )
               + COND i( WHEN p_region  IS NOT INITIAL THEN 1 ELSE 0 )
               + COND i( WHEN p_bankkey IS NOT INITIAL THEN 1 ELSE 0 ).

  IF lv_cnt > 0 AND lv_cnt < 3.
    PERFORM log_message USING 'E'
      'Ext Account Number, Region, and Bank Key must all be provided together.'.
    lv_error = abap_true.
  ENDIF.

  IF lv_error = abap_true.
    cl_bali_log_db=>get_instance( )->save_log( io_log = go_log ).
    MESSAGE e002(zoverdraft).
    STOP.
  ENDIF.

  PERFORM log_message USING 'I' 'Cross-dependency validation passed.'.

ENDFORM.


*----------------------------------------------------------------------*
* FORM call_cds_view
*----------------------------------------------------------------------*
FORM call_cds_view.

  SELECT FROM zcds_overdraft_items
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
    WHERE overdraft_since   >= @p_odsince
      AND key_date          <= @p_keydt
      AND bank_posting_area  = @p_bparea
      AND limit_type         = @p_limtype
      AND ext_acc_number IN @(
            COND #( WHEN p_extacc IS NOT INITIAL
                    THEN VALUE range_char35_tab(
                                 ( sign = 'I' option = 'EQ' low = p_extacc ) )
                    ELSE VALUE range_char35_tab( ) ) )
      AND region IN @(
            COND #( WHEN p_region IS NOT INITIAL
                    THEN VALUE range_regio_tab(
                                 ( sign = 'I' option = 'EQ' low = p_region ) )
                    ELSE VALUE range_regio_tab( ) ) )
      AND bank_key IN @(
            COND #( WHEN p_bankkey IS NOT INITIAL
                    THEN VALUE range_bankk_tab(
                                 ( sign = 'I' option = 'EQ' low = p_bankkey ) )
                    ELSE VALUE range_bankk_tab( ) ) )
      AND iban    IN @s_iban
      AND product IN @s_prod
      AND currency IN @(
            COND #( WHEN p_curr IS NOT INITIAL
                    THEN VALUE range_waers_tab(
                                 ( sign = 'I' option = 'EQ' low = p_curr ) )
                    ELSE VALUE range_waers_tab( ) ) )
      AND overdraft_amount >= @p_minovd
    INTO TABLE @gt_result.

  IF sy-subrc <> 0.
    CLEAR gt_result.
    PERFORM log_message USING 'W' 'CDS view returned no data.'.
  ELSE.
    PERFORM log_message USING 'I'
      |CDS view returned { lines( gt_result ) } record(s).|.
  ENDIF.

ENDFORM.


*----------------------------------------------------------------------*
* FORM write_spool_output
*----------------------------------------------------------------------*
FORM write_spool_output.

  IF gt_result IS INITIAL.
    WRITE: / 'No data found for the specified selection criteria.'.
    RETURN.
  ENDIF.

  NEW-PAGE LINE-SIZE 255.

  WRITE: / 'OVERDRAFT BATCH JOB – OUTPUT REPORT'.
  WRITE: / 'Overdraft Since  : ', p_odsince.
  WRITE: / 'Key Date         : ', p_keydt.
  WRITE: / 'Bank Posting Area: ', p_bparea.
  WRITE: / 'Generated On     : ', sy-datum, 'at', sy-uzeit, 'by', sy-uname.
  ULINE.

  WRITE: /1 'Ext Acc No',
          38 'IBAN',
          58 'Region',
          67 'Bank Key',
          82 'Product',
         123 'Currency',
         133 'Overdraft Amount',
         152 'Since',
         162 'Limit Type'.
  ULINE.

  LOOP AT gt_result INTO DATA(ls_result).
    WRITE: /1  ls_result-ext_acc_number,
            38 ls_result-iban,
            58 ls_result-region,
            67 ls_result-bank_key,
            82 ls_result-product,
           123 ls_result-currency,
           133 ls_result-overdraft_amount CURRENCY ls_result-currency,
           152 ls_result-overdraft_since,
           162 ls_result-limit_type.
  ENDLOOP.

  ULINE.
  WRITE: / |Total records: { lines( gt_result ) }|.

ENDFORM.


*----------------------------------------------------------------------*
* FORM log_message
*----------------------------------------------------------------------*
FORM log_message USING iv_msgty TYPE symsgty
                       iv_msg   TYPE string.

  TRY.
      DATA(lo_log) = cl_bali_log=>open_for_update( iv_handle = gv_log_handle ).
      DATA(lo_item) = cl_bali_free_text_msg=>create(
                        iv_severity = iv_msgty
                        iv_text     = iv_msg ).
      lo_log->add_item( io_item = lo_item ).
    CATCH cx_bali_runtime.
      WRITE: / '[LOG ERROR] Could not write to application log.'.
  ENDTRY.

ENDFORM.
