CLASS zcl_sc_logger_nhl DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    TYPES:
      BEGIN OF ty_result_entry,
        run_uuid         TYPE sysuuid_x16,
        result_seq       TYPE i,
        source_sheet     TYPE char20,
        source_row       TYPE i,
        contract_ref_id  TYPE char40,
        action           TYPE char6,
        service_contract TYPE char12,
        http_status      TYPE i,
        result_status    TYPE char7,
        error_code       TYPE char8,
        error_message    TYPE string,
        error_target     TYPE string,
        processed_at     TYPE utclong,
      END OF ty_result_entry,
      tt_result_entries TYPE STANDARD TABLE OF ty_result_entry WITH DEFAULT KEY.

    METHODS:
      constructor
        IMPORTING
          iv_run_uuid  TYPE sysuuid_x16
          iv_file_name TYPE string,

      add_info
        IMPORTING
          iv_text TYPE string,

      add_warning
        IMPORTING
          iv_text   TYPE string
          iv_ref_id TYPE string OPTIONAL,

      add_error
        IMPORTING
          iv_text   TYPE string
          iv_ref_id TYPE string OPTIONAL,

      add_success
        IMPORTING
          iv_text   TYPE string
          iv_ref_id TYPE string OPTIONAL,

      write_result_row
        IMPORTING
          is_entry TYPE ty_result_entry,

      flush_result_rows,

      save_log
        RETURNING
          VALUE(rv_handle) TYPE baloghndl,

      get_next_seq
        RETURNING
          VALUE(rv_seq) TYPE i.

  PRIVATE SECTION.

    DATA:
      mo_log       TYPE REF TO if_bali_log,
      mv_run_uuid  TYPE sysuuid_x16,
      mt_results   TYPE tt_result_entries,
      mv_seq       TYPE i.

    METHODS:
      add_free_text
        IMPORTING
          iv_severity TYPE if_bali_constants=>ty_severity
          iv_text     TYPE string.

ENDCLASS.


CLASS zcl_sc_logger_nhl IMPLEMENTATION.

  METHOD constructor.
    mv_run_uuid = iv_run_uuid.
    mv_seq      = 0.

    mo_log = cl_bali_log=>create_with_header(
               header = cl_bali_header_setter=>create(
                          object    = 'Z_BO_SCUP_NHL'
                          subobject = CONV #( mv_run_uuid )
                          extnumber = iv_file_name ) ).
  ENDMETHOD.


  METHOD add_info.
    add_free_text( iv_severity = if_bali_constants=>c_severity_status
                   iv_text     = iv_text ).
  ENDMETHOD.


  METHOD add_warning.
    DATA(lv_text) = COND #( WHEN iv_ref_id IS NOT INITIAL
                            THEN |[{ iv_ref_id }] { iv_text }|
                            ELSE iv_text ).
    add_free_text( iv_severity = if_bali_constants=>c_severity_warning
                   iv_text     = lv_text ).
  ENDMETHOD.


  METHOD add_error.
    DATA(lv_text) = COND #( WHEN iv_ref_id IS NOT INITIAL
                            THEN |[{ iv_ref_id }] { iv_text }|
                            ELSE iv_text ).
    add_free_text( iv_severity = if_bali_constants=>c_severity_error
                   iv_text     = lv_text ).
  ENDMETHOD.


  METHOD add_success.
    DATA(lv_text) = COND #( WHEN iv_ref_id IS NOT INITIAL
                            THEN |[{ iv_ref_id }] { iv_text }|
                            ELSE iv_text ).
    add_free_text( iv_severity = if_bali_constants=>c_severity_status
                   iv_text     = lv_text ).
  ENDMETHOD.


  METHOD add_free_text.
    TRY.
        mo_log->add_item(
          item = cl_bali_free_text_setter=>create(
                   severity = iv_severity
                   text     = iv_text ) ).
      CATCH cx_bali_runtime.
        " Silent — logging must not interrupt processing
    ENDTRY.
  ENDMETHOD.


  METHOD write_result_row.
    APPEND is_entry TO mt_results.
  ENDMETHOD.


  METHOD get_next_seq.
    ADD 1 TO mv_seq.
    rv_seq = mv_seq.
  ENDMETHOD.


  METHOD flush_result_rows.
    LOOP AT mt_results INTO DATA(ls_entry).
      INSERT INTO zsc_upload_res_nhl VALUES @(
        VALUE zsc_upload_res_nhl(
          mandt           = sy-mandt
          upload_run_uuid = ls_entry-run_uuid
          result_seq      = ls_entry-result_seq
          source_sheet    = ls_entry-source_sheet
          source_row      = ls_entry-source_row
          contract_ref_id = ls_entry-contract_ref_id
          action          = ls_entry-action
          service_contract = ls_entry-service_contract
          http_status     = ls_entry-http_status
          result_status   = ls_entry-result_status
          error_code      = ls_entry-error_code
          error_message   = ls_entry-error_message
          error_target    = ls_entry-error_target
          processed_at    = ls_entry-processed_at
        )
      ).
    ENDLOOP.
    CLEAR mt_results.
  ENDMETHOD.


  METHOD save_log.
    TRY.
        DATA(lo_db) = cl_bali_log_db=>get_instance( ).
        lo_db->save_log( log = mo_log ).
        rv_handle = mo_log->get_handle( ).
      CATCH cx_bali_runtime.
        " Return empty handle — processing continues
    ENDTRY.
  ENDMETHOD.

ENDCLASS.
