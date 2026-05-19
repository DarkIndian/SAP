*&---------------------------------------------------------------------*
*& Class        : ZCL_BATCH_OVERDRAFT_JOB
*& Description  : Application Job Framework – Overdraft Batch Job
*&
*& Implements   : IF_APJ_DT_EXEC_OBJECT  (parameter catalog)
*&                IF_APJ_RT_RUN          (execution at runtime)
*&
*& Scheduling   : F1240 / External Scheduler / API / Recurring
*&---------------------------------------------------------------------*
CLASS zcl_batch_overdraft_job DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    INTERFACES if_apj_dt_exec_object.
    INTERFACES if_apj_rt_run.

    "-- Parameter name constants (used in catalog + execute) ----------
    CONSTANTS:
      gc_p_odsince   TYPE if_apj_dt_exec_object=>ty_element-name VALUE 'P_ODSINCE',
      gc_p_keydt     TYPE if_apj_dt_exec_object=>ty_element-name VALUE 'P_KEYDT',
      gc_p_bparea    TYPE if_apj_dt_exec_object=>ty_element-name VALUE 'P_BPAREA',
      gc_p_spool     TYPE if_apj_dt_exec_object=>ty_element-name VALUE 'P_SPOOL',
      gc_p_limtype   TYPE if_apj_dt_exec_object=>ty_element-name VALUE 'P_LIMTYPE',
      gc_s_extacc    TYPE if_apj_dt_exec_object=>ty_element-name VALUE 'S_EXTACC',
      gc_s_region    TYPE if_apj_dt_exec_object=>ty_element-name VALUE 'S_REGION',
      gc_s_bankkey   TYPE if_apj_dt_exec_object=>ty_element-name VALUE 'S_BANKKEY',
      gc_s_iban      TYPE if_apj_dt_exec_object=>ty_element-name VALUE 'S_IBAN',
      gc_s_product   TYPE if_apj_dt_exec_object=>ty_element-name VALUE 'S_PRODUCT',
      gc_p_curr      TYPE if_apj_dt_exec_object=>ty_element-name VALUE 'P_CURR',
      gc_p_minovd    TYPE if_apj_dt_exec_object=>ty_element-name VALUE 'P_MINOVD'.

    "-- Limit type domain values --------------------------------------
    CONSTANTS:
      gc_lim_nolimit  TYPE char10 VALUE 'NOLIMIT',
      gc_lim_external TYPE char10 VALUE 'EXTLIMIT',
      gc_lim_internal TYPE char10 VALUE 'INTLIMIT'.

  PRIVATE SECTION.

    "-- Internal result type (adapt fields to your CDS view) ----------
    TYPES:
      BEGIN OF ty_overdraft_result,
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
      END OF ty_overdraft_result,
      tt_overdraft_result TYPE STANDARD TABLE OF ty_overdraft_result
                          WITH DEFAULT KEY.

    "-- Helper methods ------------------------------------------------
    METHODS:

      validate_cross_dependencies
        IMPORTING
          iv_currency       TYPE waers
          iv_min_overdraft  TYPE wertv8
          iv_ext_acc_number TYPE char35
          iv_region         TYPE regio
          iv_bank_key       TYPE bankk
        RETURNING
          VALUE(rv_valid)   TYPE abap_bool,

      check_authorization
        IMPORTING
          iv_bank_posting_area TYPE char10
        RETURNING
          VALUE(rv_authorized) TYPE abap_bool,

      fill_from_config
        IMPORTING
          iv_config_key        TYPE char20 DEFAULT 'DEFAULT'
        CHANGING
          cv_overdraft_since   TYPE dats
          cv_key_date          TYPE dats
          cv_bank_posting_area TYPE char10
          cv_limit_type        TYPE char10
          cv_ext_acc_number    TYPE char35
          cv_region            TYPE regio
          cv_bank_key          TYPE bankk
          cv_currency          TYPE waers
          cv_min_overdraft     TYPE wertv8,

      call_cds_view
        IMPORTING
          iv_overdraft_since   TYPE dats
          iv_key_date          TYPE dats
          iv_bank_posting_area TYPE char10
          iv_limit_type        TYPE char10
          iv_ext_acc_number    TYPE char35
          iv_region            TYPE regio
          iv_bank_key          TYPE bankk
          it_iban              TYPE if_apj_rt_run=>tt_parameter_val
          it_products          TYPE if_apj_rt_run=>tt_parameter_val
          iv_currency          TYPE waers
          iv_min_overdraft     TYPE wertv8
        EXPORTING
          et_result            TYPE tt_overdraft_result,

      write_spool_output
        IMPORTING
          it_result            TYPE tt_overdraft_result
          iv_overdraft_since   TYPE dats
          iv_key_date          TYPE dats
          iv_bank_posting_area TYPE char10,

      log_message
        IMPORTING
          iv_msgty TYPE symsgty
          iv_msg   TYPE string.

    DATA: mv_log_handle TYPE if_bali_log=>ty_handle.

ENDCLASS.


CLASS zcl_batch_overdraft_job IMPLEMENTATION.

*----------------------------------------------------------------------*
* IF_APJ_DT_EXEC_OBJECT~GET_PARAMETERS
* Called by the AJF framework to retrieve the parameter catalog.
* Defines which parameters appear in the job template (F1240).
*----------------------------------------------------------------------*
  METHOD if_apj_dt_exec_object~get_parameters.

    DATA lt_catalog TYPE if_apj_dt_exec_object=>tt_catalog_item.

    "-- Mandatory: Overdraft Since Date
    APPEND VALUE #(
      name             = gc_p_odsince
      text             = 'Overdraft Since Date'
      kind             = if_apj_dt_exec_object=>cs_parameter_kind-data
      data_type_name   = 'DATS'
      is_mandatory     = abap_true
    ) TO lt_catalog.

    "-- Mandatory: Key Date
    APPEND VALUE #(
      name             = gc_p_keydt
      text             = 'Key Date'
      kind             = if_apj_dt_exec_object=>cs_parameter_kind-data
      data_type_name   = 'DATS'
      is_mandatory     = abap_true
    ) TO lt_catalog.

    "-- Mandatory: Bank Posting Area
    APPEND VALUE #(
      name             = gc_p_bparea
      text             = 'Bank Posting Area'
      kind             = if_apj_dt_exec_object=>cs_parameter_kind-data
      data_type_name   = 'CHAR10'
      is_mandatory     = abap_true
    ) TO lt_catalog.

    "-- Mandatory: Spool (radio button – store 'X'/'')
    APPEND VALUE #(
      name             = gc_p_spool
      text             = 'Spool Output'
      kind             = if_apj_dt_exec_object=>cs_parameter_kind-data
      data_type_name   = 'CHAR1'
      is_mandatory     = abap_true
    ) TO lt_catalog.

    "-- Mandatory: Limit Type (domain ZDE_LIMIT_TYPE: NOLIMIT/EXTLIMIT/INTLIMIT)
    APPEND VALUE #(
      name             = gc_p_limtype
      text             = 'Limit Type'
      kind             = if_apj_dt_exec_object=>cs_parameter_kind-data
      data_type_name   = 'CHAR10'
      domain_name      = 'ZDE_LIMIT_TYPE'
      is_mandatory     = abap_true
    ) TO lt_catalog.

    "-- Optional: External Account Number
    APPEND VALUE #(
      name             = gc_s_extacc
      text             = 'External Account Number'
      kind             = if_apj_dt_exec_object=>cs_parameter_kind-data
      data_type_name   = 'CHAR35'
      is_mandatory     = abap_false
    ) TO lt_catalog.

    "-- Optional: Region
    APPEND VALUE #(
      name             = gc_s_region
      text             = 'Region'
      kind             = if_apj_dt_exec_object=>cs_parameter_kind-data
      data_type_name   = 'REGIO'
      is_mandatory     = abap_false
    ) TO lt_catalog.

    "-- Optional: Bank Key
    APPEND VALUE #(
      name             = gc_s_bankkey
      text             = 'Bank Key'
      kind             = if_apj_dt_exec_object=>cs_parameter_kind-data
      data_type_name   = 'BANKK'
      is_mandatory     = abap_false
    ) TO lt_catalog.

    "-- Optional: IBAN (multi-value / table-type via select-options)
    APPEND VALUE #(
      name             = gc_s_iban
      text             = 'IBAN'
      kind             = if_apj_dt_exec_object=>cs_parameter_kind-selection_condition
      data_type_name   = 'IBAN'
      is_mandatory     = abap_false
    ) TO lt_catalog.

    "-- Optional: Products (multi-value)
    APPEND VALUE #(
      name             = gc_s_product
      text             = 'Product(s)'
      kind             = if_apj_dt_exec_object=>cs_parameter_kind-selection_condition
      data_type_name   = 'CHAR40'
      is_mandatory     = abap_false
    ) TO lt_catalog.

    "-- Optional: Currency
    APPEND VALUE #(
      name             = gc_p_curr
      text             = 'Currency'
      kind             = if_apj_dt_exec_object=>cs_parameter_kind-data
      data_type_name   = 'WAERS'
      is_mandatory     = abap_false
    ) TO lt_catalog.

    "-- Optional: Minimum Overdraft
    APPEND VALUE #(
      name             = gc_p_minovd
      text             = 'Minimum Overdraft'
      kind             = if_apj_dt_exec_object=>cs_parameter_kind-data
      data_type_name   = 'WERTV8'
      is_mandatory     = abap_false
    ) TO lt_catalog.

    et_parameter_catalog = lt_catalog.

  ENDMETHOD.


*----------------------------------------------------------------------*
* IF_APJ_RT_RUN~EXECUTE
* Entry point called by the AJF scheduler at runtime.
*----------------------------------------------------------------------*
  METHOD if_apj_rt_run~execute.

    "--------------------------------------------------------------------
    " 0. Initialise Application Log
    "--------------------------------------------------------------------
    DATA(lo_log) = cl_bali_log=>create_with_header(
                     iv_object    = 'ZOVERDRAFT'
                     iv_subobject = 'BATCH' ).
    mv_log_handle = lo_log->get_handle( ).

    log_message( iv_msgty = 'I'
                 iv_msg   = 'Overdraft batch job started.' ).

    "--------------------------------------------------------------------
    " 1. Extract parameters from the runtime parameter table
    "--------------------------------------------------------------------
    DATA lv_odsince   TYPE dats.
    DATA lv_keydt     TYPE dats.
    DATA lv_bparea    TYPE char10.
    DATA lv_spool     TYPE char1.
    DATA lv_limtype   TYPE char10.
    DATA lv_extacc    TYPE char35.
    DATA lv_region    TYPE regio.
    DATA lv_bankkey   TYPE bankk.
    DATA lv_curr      TYPE waers.
    DATA lv_minovd    TYPE wertv8.
    DATA lt_iban      TYPE if_apj_rt_run=>tt_parameter_val.
    DATA lt_product   TYPE if_apj_rt_run=>tt_parameter_val.

    LOOP AT it_parameters INTO DATA(ls_param).
      CASE ls_param-name.
        WHEN gc_p_odsince.  lv_odsince  = ls_param-value.
        WHEN gc_p_keydt.    lv_keydt    = ls_param-value.
        WHEN gc_p_bparea.   lv_bparea   = ls_param-value.
        WHEN gc_p_spool.    lv_spool    = ls_param-value.
        WHEN gc_p_limtype.  lv_limtype  = ls_param-value.
        WHEN gc_s_extacc.   lv_extacc   = ls_param-value.
        WHEN gc_s_region.   lv_region   = ls_param-value.
        WHEN gc_s_bankkey.  lv_bankkey  = ls_param-value.
        WHEN gc_s_iban.     APPEND ls_param TO lt_iban.
        WHEN gc_s_product.  APPEND ls_param TO lt_product.
        WHEN gc_p_curr.     lv_curr     = ls_param-value.
        WHEN gc_p_minovd.   lv_minovd   = ls_param-value.
      ENDCASE.
    ENDLOOP.

    "--------------------------------------------------------------------
    " 2. Fill blanks from configuration table
    "--------------------------------------------------------------------
    fill_from_config(
      CHANGING
        cv_overdraft_since   = lv_odsince
        cv_key_date          = lv_keydt
        cv_bank_posting_area = lv_bparea
        cv_limit_type        = lv_limtype
        cv_ext_acc_number    = lv_extacc
        cv_region            = lv_region
        cv_bank_key          = lv_bankkey
        cv_currency          = lv_curr
        cv_min_overdraft     = lv_minovd ).

    "--------------------------------------------------------------------
    " 3. Authorization check
    "--------------------------------------------------------------------
    IF check_authorization( lv_bparea ) = abap_false.
      log_message( iv_msgty = 'E'
                   iv_msg   = 'Authorization check failed. Job terminated.' ).
      cl_bali_log_db=>get_instance( )->save_log( io_log = lo_log ).
      RETURN.
    ENDIF.

    log_message( iv_msgty = 'I' iv_msg = 'Authorization check passed.' ).

    "--------------------------------------------------------------------
    " 4. Cross-dependency validation
    "--------------------------------------------------------------------
    IF validate_cross_dependencies(
         iv_currency       = lv_curr
         iv_min_overdraft  = lv_minovd
         iv_ext_acc_number = lv_extacc
         iv_region         = lv_region
         iv_bank_key       = lv_bankkey ) = abap_false.

      log_message( iv_msgty = 'E'
                   iv_msg   = 'Cross-dependency validation failed. Job terminated.' ).
      cl_bali_log_db=>get_instance( )->save_log( io_log = lo_log ).
      RETURN.
    ENDIF.

    log_message( iv_msgty = 'I' iv_msg = 'Cross-dependency validation passed.' ).

    "--------------------------------------------------------------------
    " 5. Call CDS view / business logic
    "--------------------------------------------------------------------
    DATA lt_result TYPE tt_overdraft_result.

    call_cds_view(
      EXPORTING
        iv_overdraft_since   = lv_odsince
        iv_key_date          = lv_keydt
        iv_bank_posting_area = lv_bparea
        iv_limit_type        = lv_limtype
        iv_ext_acc_number    = lv_extacc
        iv_region            = lv_region
        iv_bank_key          = lv_bankkey
        it_iban              = lt_iban
        it_products          = lt_product
        iv_currency          = lv_curr
        iv_min_overdraft     = lv_minovd
      IMPORTING
        et_result            = lt_result ).

    "--------------------------------------------------------------------
    " 6. Spool output
    "--------------------------------------------------------------------
    IF lt_result IS INITIAL.
      log_message( iv_msgty = 'W'
                   iv_msg   = 'CDS view returned no data. No spool output generated.' ).
    ELSE.
      IF lv_spool = abap_true.
        write_spool_output(
          it_result            = lt_result
          iv_overdraft_since   = lv_odsince
          iv_key_date          = lv_keydt
          iv_bank_posting_area = lv_bparea ).
        log_message( iv_msgty = 'S'
                     iv_msg   = |Spool output written – { lines( lt_result ) } record(s).| ).
      ENDIF.
    ENDIF.

    "--------------------------------------------------------------------
    " 7. Save Application Log
    "--------------------------------------------------------------------
    log_message( iv_msgty = 'I' iv_msg = 'Overdraft batch job completed.' ).
    cl_bali_log_db=>get_instance( )->save_log( io_log = lo_log ).

  ENDMETHOD.


*----------------------------------------------------------------------*
* VALIDATE_CROSS_DEPENDENCIES
* Rule I : Currency + Minimum Overdraft – both or neither.
* Rule II: Ext Acc Number + Region + Bank Key – all or none.
*----------------------------------------------------------------------*
  METHOD validate_cross_dependencies.

    rv_valid = abap_true.

    "-- Rule I: Currency ↔ Minimum Overdraft
    IF ( iv_currency IS NOT INITIAL AND iv_min_overdraft IS INITIAL ) OR
       ( iv_currency IS INITIAL     AND iv_min_overdraft IS NOT INITIAL ).
      log_message( iv_msgty = 'E'
                   iv_msg   = 'Currency and Minimum Overdraft must both be filled or both be empty.' ).
      rv_valid = abap_false.
    ENDIF.

    "-- Rule II: Ext Acc Number, Region, Bank Key – all three or none
    DATA(lv_filled_count) = COND i(
      WHEN iv_ext_acc_number IS NOT INITIAL THEN 1 ELSE 0 ) +
      COND i( WHEN iv_region         IS NOT INITIAL THEN 1 ELSE 0 ) +
      COND i( WHEN iv_bank_key       IS NOT INITIAL THEN 1 ELSE 0 ).

    IF lv_filled_count > 0 AND lv_filled_count < 3.
      log_message( iv_msgty = 'E'
                   iv_msg   = 'External Account Number, Region, and Bank Key must all be filled when any one is provided.' ).
      rv_valid = abap_false.
    ENDIF.

  ENDMETHOD.


*----------------------------------------------------------------------*
* CHECK_AUTHORIZATION
*----------------------------------------------------------------------*
  METHOD check_authorization.

    AUTHORITY-CHECK OBJECT 'Z_OD_JOB'
      ID 'ACTVT'   FIELD '16'
      ID 'Z_BPAREA' FIELD iv_bank_posting_area.

    rv_authorized = COND #( WHEN sy-subrc = 0 THEN abap_true ELSE abap_false ).

    IF rv_authorized = abap_false.
      log_message( iv_msgty = 'E'
                   iv_msg   = |User { sy-uname } is not authorized to execute the overdraft job for bank posting area { iv_bank_posting_area }.| ).
    ENDIF.

  ENDMETHOD.


*----------------------------------------------------------------------*
* FILL_FROM_CONFIG
* Reads ZTOVERDRAFT_CONFIG and fills any blank parameter with the
* stored default.  User-supplied values are never overwritten.
*----------------------------------------------------------------------*
  METHOD fill_from_config.

    SELECT SINGLE *
      FROM ztoverdraft_config
      WHERE mandt      = @sy-mandt
        AND config_key = @iv_config_key
      INTO @DATA(ls_config).

    IF sy-subrc <> 0.
      log_message( iv_msgty = 'W'
                   iv_msg   = |Configuration key '{ iv_config_key }' not found in ZTOVERDRAFT_CONFIG.| ).
      RETURN.
    ENDIF.

    IF cv_overdraft_since   IS INITIAL. cv_overdraft_since   = ls_config-overdraft_since.   ENDIF.
    IF cv_key_date          IS INITIAL. cv_key_date          = ls_config-key_date.           ENDIF.
    IF cv_bank_posting_area IS INITIAL. cv_bank_posting_area = ls_config-bank_posting_area.  ENDIF.
    IF cv_limit_type        IS INITIAL. cv_limit_type        = ls_config-limit_type.         ENDIF.
    IF cv_ext_acc_number    IS INITIAL. cv_ext_acc_number    = ls_config-ext_acc_number.     ENDIF.
    IF cv_region            IS INITIAL. cv_region            = ls_config-region.             ENDIF.
    IF cv_bank_key          IS INITIAL. cv_bank_key          = ls_config-bank_key.           ENDIF.
    IF cv_currency          IS INITIAL. cv_currency          = ls_config-currency.           ENDIF.
    IF cv_min_overdraft     IS INITIAL. cv_min_overdraft     = ls_config-min_overdraft.      ENDIF.

    log_message( iv_msgty = 'I'
                 iv_msg   = 'Default values applied from configuration table where parameters were blank.' ).

  ENDMETHOD.


*----------------------------------------------------------------------*
* CALL_CDS_VIEW
* Calls the Overdraft CDS consumption view and returns results.
* Replace ZCDS_OVERDRAFT_ITEMS with your actual CDS view name.
*----------------------------------------------------------------------*
  METHOD call_cds_view.

    "-- Build IBAN range table from AJF parameter list
    DATA lt_iban_range TYPE RANGE OF iban.
    LOOP AT it_iban INTO DATA(ls_iban_param).
      APPEND VALUE #( sign   = ls_iban_param-sign
                      option = ls_iban_param-option
                      low    = ls_iban_param-low
                      high   = ls_iban_param-high ) TO lt_iban_range.
    ENDLOOP.

    "-- Build product range table
    DATA lt_product_range TYPE RANGE OF char40.
    LOOP AT it_products INTO DATA(ls_prod_param).
      APPEND VALUE #( sign   = ls_prod_param-sign
                      option = ls_prod_param-option
                      low    = ls_prod_param-low
                      high   = ls_prod_param-high ) TO lt_product_range.
    ENDLOOP.

    "-- Query CDS view
    "  ZCDS_OVERDRAFT_ITEMS is the CDS consumption view.
    "  Adjust field names to match your actual CDS annotation/projection.
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
      WHERE overdraft_since   >= @iv_overdraft_since
        AND key_date          <= @iv_key_date
        AND bank_posting_area  = @iv_bank_posting_area
        AND limit_type         = @iv_limit_type
        AND ext_acc_number IN @(
              COND #( WHEN iv_ext_acc_number IS NOT INITIAL
                      THEN VALUE range_char35_tab(
                                   ( sign = 'I' option = 'EQ' low = iv_ext_acc_number ) )
                      ELSE VALUE range_char35_tab( ) ) )
        AND region IN @(
              COND #( WHEN iv_region IS NOT INITIAL
                      THEN VALUE range_regio_tab(
                                   ( sign = 'I' option = 'EQ' low = iv_region ) )
                      ELSE VALUE range_regio_tab( ) ) )
        AND bank_key IN @(
              COND #( WHEN iv_bank_key IS NOT INITIAL
                      THEN VALUE range_bankk_tab(
                                   ( sign = 'I' option = 'EQ' low = iv_bank_key ) )
                      ELSE VALUE range_bankk_tab( ) ) )
        AND iban IN @lt_iban_range
        AND product IN @lt_product_range
        AND currency IN @(
              COND #( WHEN iv_currency IS NOT INITIAL
                      THEN VALUE range_waers_tab(
                                   ( sign = 'I' option = 'EQ' low = iv_currency ) )
                      ELSE VALUE range_waers_tab( ) ) )
        AND overdraft_amount >= @iv_min_overdraft
      INTO TABLE @et_result.

    IF sy-subrc <> 0.
      CLEAR et_result.
    ENDIF.

  ENDMETHOD.


*----------------------------------------------------------------------*
* WRITE_SPOOL_OUTPUT
* Writes results to the job spool using ABAP List Processing.
*----------------------------------------------------------------------*
  METHOD write_spool_output.

    NEW-PAGE LINE-SIZE 255.

    WRITE: / 'OVERDRAFT BATCH JOB – OUTPUT REPORT'.
    WRITE: / 'Overdraft Since : ', iv_overdraft_since.
    WRITE: / 'Key Date        : ', iv_key_date.
    WRITE: / 'Bank Posting Area:', iv_bank_posting_area.
    WRITE: / 'Generated On    : ', sy-datum, 'at', sy-uzeit, 'by', sy-uname.
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

    LOOP AT it_result INTO DATA(ls_result).
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
    WRITE: / |Total records: { lines( it_result ) }|.

  ENDMETHOD.


*----------------------------------------------------------------------*
* LOG_MESSAGE
*----------------------------------------------------------------------*
  METHOD log_message.

    TRY.
        DATA(lo_log) = cl_bali_log=>open_for_update( iv_handle = mv_log_handle ).

        DATA(lo_msg) = cl_bali_free_text_msg=>create(
                         iv_severity  = iv_msgty
                         iv_text      = iv_msg ).

        lo_log->add_item( io_item = lo_msg ).
      CATCH cx_bali_runtime INTO DATA(lx_bali).
        " Log unavailable – silent fall-through; do not interrupt job
        WRITE: / '[LOG ERROR]', lx_bali->get_text( ).
    ENDTRY.

  ENDMETHOD.

ENDCLASS.
