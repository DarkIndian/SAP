CLASS zcl_sc_upload_orch_nhl DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    TYPES:
      BEGIN OF ty_process_result,
        overall_status    TYPE zde_sc_run_status_nhl,
        total_records     TYPE i,
        success_count     TYPE i,
        failed_count      TYPE i,
        file_size_bytes   TYPE int8,
        file_hash         TYPE char40,
        bali_log_handle   TYPE baloghndl,
      END OF ty_process_result.

    CLASS-METHODS process_upload
      IMPORTING
        iv_run_uuid    TYPE sysuuid_x16
        iv_file_content TYPE xstring
        iv_file_name    TYPE string
      RETURNING
        VALUE(rs_result) TYPE ty_process_result
      RAISING
        cx_sy_conversion_error.

    CLASS-METHODS reprocess_failed
      IMPORTING
        iv_run_uuid      TYPE sysuuid_x16
      RETURNING
        VALUE(rs_result) TYPE ty_process_result.

  PRIVATE SECTION.

    CLASS-METHODS compute_sha1
      IMPORTING
        iv_xstring       TYPE xstring
      RETURNING
        VALUE(rv_hash)   TYPE char40.

    CLASS-METHODS execute_row
      IMPORTING
        is_header        TYPE zcl_sc_xlsx_reader_nhl=>ty_header_row
        it_items         TYPE zcl_sc_xlsx_reader_nhl=>tt_item_rows
        it_billing       TYPE zcl_sc_xlsx_reader_nhl=>tt_billing_rows
        it_partners      TYPE zcl_sc_xlsx_reader_nhl=>tt_partner_rows
        io_logger        TYPE REF TO zcl_sc_logger_nhl
        io_client        TYPE REF TO zcl_sc_api_client_nhl
        iv_seq           TYPE i
      CHANGING
        cv_success_count TYPE i
        cv_failed_count  TYPE i.

ENDCLASS.


CLASS zcl_sc_upload_orch_nhl IMPLEMENTATION.

  METHOD process_upload.

    " ── 1. Compute file metadata ─────────────────────────────────────────
    rs_result-file_size_bytes = xstrlen( iv_file_content ).
    rs_result-file_hash       = compute_sha1( iv_file_content ).

    " ── 2. Parse XLSX ────────────────────────────────────────────────────
    DATA(ls_parsed) = zcl_sc_xlsx_reader_nhl=>parse(
                        iv_file_content = iv_file_content
                        iv_file_name    = iv_file_name ).

    " ── 3. Open application log ──────────────────────────────────────────
    DATA(lo_logger) = NEW zcl_sc_logger_nhl( iv_run_uuid = iv_run_uuid ).

    " ── 4. Pre-validate all rows ─────────────────────────────────────────
    DATA(lt_errors) = zcl_sc_prevalidator_nhl=>validate( ls_parsed ).

    IF lt_errors IS NOT INITIAL.
      " Log every validation error and mark run as FAILED
      LOOP AT lt_errors INTO DATA(ls_err).
        lo_logger->add_error(
          iv_text => |{ ls_err-error_code }: { ls_err-error_text } [row { ls_err-excel_row }]| ).
        lo_logger->write_result_row(
          iv_seq        = sy-tabix
          iv_sheet      = ls_err-sheet
          iv_source_row = ls_err-excel_row
          iv_ref_id     = ls_err-ref_id
          iv_action     = ''
          iv_status     = 'ERROR'
          iv_error_code = ls_err-error_code
          iv_error_msg  = ls_err-error_text
          iv_error_tgt  = '' ).
      ENDLOOP.

      lo_logger->flush_result_rows( iv_run_uuid = iv_run_uuid ).
      rs_result-bali_log_handle = lo_logger->save_log( ).
      rs_result-overall_status  = 'FAILED'.
      rs_result-total_records   = lines( ls_parsed-header_rows ).
      rs_result-failed_count    = lines( lt_errors ).
      RETURN.
    ENDIF.

    " ── 5. Instantiate API client ─────────────────────────────────────────
    DATA(lo_client) = NEW zcl_sc_api_client_nhl( ).

    " ── 6. Process each header row ────────────────────────────────────────
    DATA(lv_seq) = 0.
    LOOP AT ls_parsed-header_rows INTO DATA(ls_hdr).
      lv_seq += 1.

      " Collect sub-rows for this contract reference
      DATA lt_items   TYPE zcl_sc_xlsx_reader_nhl=>tt_item_rows.
      DATA lt_billing TYPE zcl_sc_xlsx_reader_nhl=>tt_billing_rows.
      DATA lt_partners TYPE zcl_sc_xlsx_reader_nhl=>tt_partner_rows.

      lt_items   = VALUE #( FOR r IN ls_parsed-item_rows
                              WHERE ( contract_ref_id = ls_hdr-contract_ref_id ) ( r ) ).
      lt_billing = VALUE #( FOR r IN ls_parsed-billing_rows
                              WHERE ( contract_ref_id = ls_hdr-contract_ref_id ) ( r ) ).
      lt_partners = VALUE #( FOR r IN ls_parsed-partner_rows
                               WHERE ( contract_ref_id = ls_hdr-contract_ref_id ) ( r ) ).

      execute_row(
        EXPORTING
          is_header        = ls_hdr
          it_items         = lt_items
          it_billing       = lt_billing
          it_partners      = lt_partners
          io_logger        = lo_logger
          io_client        = lo_client
          iv_seq           = lv_seq
        CHANGING
          cv_success_count = rs_result-success_count
          cv_failed_count  = rs_result-failed_count ).

      CLEAR: lt_items, lt_billing, lt_partners.
    ENDLOOP.

    " ── 7. Flush results and save log ─────────────────────────────────────
    lo_logger->flush_result_rows( iv_run_uuid = iv_run_uuid ).
    rs_result-bali_log_handle = lo_logger->save_log( ).
    rs_result-total_records   = lv_seq.

    IF rs_result-failed_count = 0.
      rs_result-overall_status = 'COMPLETED'.
    ELSEIF rs_result-success_count = 0.
      rs_result-overall_status = 'FAILED'.
    ELSE.
      rs_result-overall_status = 'COMPLETED'.   " partial success = COMPLETED
    ENDIF.

  ENDMETHOD.


  METHOD reprocess_failed.

    " Read failed result rows for this run
    SELECT upload_run_uuid,
           result_seq,
           source_sheet,
           source_row,
           contract_ref_id,
           action
      FROM zsc_upload_res_nhl
      WHERE upload_run_uuid = @iv_run_uuid
        AND result_status   = 'ERROR'
      INTO TABLE @DATA(lt_failed).

    IF lt_failed IS INITIAL.
      rs_result-overall_status = 'COMPLETED'.
      RETURN.
    ENDIF.

    " Re-read original file content from run header
    SELECT SINGLE file_name, file_hash
      FROM zsc_upload_run_nhl
      WHERE upload_run_uuid = @iv_run_uuid
      INTO @DATA(ls_run).

    IF sy-subrc <> 0.
      rs_result-overall_status = 'FAILED'.
      RETURN.
    ENDIF.

    " Cannot re-parse without file content in DB — log warning and exit
    DATA(lo_logger) = NEW zcl_sc_logger_nhl( iv_run_uuid = iv_run_uuid ).
    lo_logger->add_warning( 'Reprocess: original file content not stored; cannot re-parse.' ).
    lo_logger->flush_result_rows( iv_run_uuid = iv_run_uuid ).
    rs_result-bali_log_handle = lo_logger->save_log( ).
    rs_result-overall_status  = 'FAILED'.
    rs_result-total_records   = lines( lt_failed ).
    rs_result-failed_count    = lines( lt_failed ).

  ENDMETHOD.


  METHOD execute_row.

    " Build payload from parsed rows
    DATA ls_payload TYPE zif_sc_api_client_nhl=>ty_header_payload.
    DATA lt_items   TYPE zif_sc_api_client_nhl=>tt_item_payload.

    TRY.
        zcl_sc_payload_bldr_nhl=>build(
          EXPORTING
            is_header   = is_header
            it_items    = it_items
            it_billing  = it_billing
            it_partners = it_partners
          IMPORTING
            es_payload  = ls_payload
            et_items    = lt_items ).
      CATCH cx_sy_conversion_error INTO DATA(lx_conv).
        io_logger->add_error( |Payload build error for ref { is_header-contract_ref_id }: { lx_conv->get_text( ) }| ).
        io_logger->write_result_row(
          iv_seq        = iv_seq
          iv_sheet      = 'Header'
          iv_source_row = is_header-excel_row
          iv_ref_id     = is_header-contract_ref_id
          iv_action     = is_header-action
          iv_status     = 'ERROR'
          iv_error_code = 'SCUP_090'
          iv_error_msg  = lx_conv->get_text( )
          iv_error_tgt  = '' ).
        cv_failed_count += 1.
        RETURN.
    ENDTRY.

    " Call the OData API
    DATA ls_api_result TYPE zif_sc_api_client_nhl=>ty_api_result.

    TRY.
        IF is_header-action = 'UPDATE'.
          io_client->update_contract(
            EXPORTING
              is_header  = ls_payload
              it_items   = lt_items
            IMPORTING
              es_result  = ls_api_result ).
        ELSE.
          io_client->create_contract(
            EXPORTING
              is_header  = ls_payload
              it_items   = lt_items
            IMPORTING
              es_result  = ls_api_result ).
        ENDIF.
      CATCH cx_sy_conversion_error INTO DATA(lx_api).
        io_logger->add_error( |API call failed for ref { is_header-contract_ref_id }: { lx_api->get_text( ) }| ).
        io_logger->write_result_row(
          iv_seq        = iv_seq
          iv_sheet      = 'Header'
          iv_source_row = is_header-excel_row
          iv_ref_id     = is_header-contract_ref_id
          iv_action     = is_header-action
          iv_status     = 'ERROR'
          iv_error_code = 'SCUP_100'
          iv_error_msg  = lx_api->get_text( )
          iv_error_tgt  = '' ).
        cv_failed_count += 1.
        RETURN.
    ENDTRY.

    " Log result row
    IF ls_api_result-http_status >= 200 AND ls_api_result-http_status < 300.
      io_logger->add_success( |Created/Updated: { ls_api_result-service_contract } [ref { is_header-contract_ref_id }]| ).
      io_logger->write_result_row(
        iv_seq             = iv_seq
        iv_sheet           = 'Header'
        iv_source_row      = is_header-excel_row
        iv_ref_id          = is_header-contract_ref_id
        iv_action          = is_header-action
        iv_service_contract = ls_api_result-service_contract
        iv_http_status     = ls_api_result-http_status
        iv_status          = 'SUCCESS'
        iv_error_code      = ''
        iv_error_msg       = ''
        iv_error_tgt       = '' ).
      cv_success_count += 1.
    ELSE.
      io_logger->add_error( |API error { ls_api_result-http_status } for ref { is_header-contract_ref_id }: { ls_api_result-error_message }| ).
      io_logger->write_result_row(
        iv_seq             = iv_seq
        iv_sheet           = 'Header'
        iv_source_row      = is_header-excel_row
        iv_ref_id          = is_header-contract_ref_id
        iv_action          = is_header-action
        iv_service_contract = ls_api_result-service_contract
        iv_http_status     = ls_api_result-http_status
        iv_status          = 'ERROR'
        iv_error_code      = ls_api_result-error_code
        iv_error_msg       = ls_api_result-error_message
        iv_error_tgt       = ls_api_result-error_target ).
      cv_failed_count += 1.
    ENDIF.

  ENDMETHOD.


  METHOD compute_sha1.
    " Use ABAP Cloud released cl_abap_message_digest for SHA-1
    TRY.
        cl_abap_message_digest=>calculate_hash_for_raw(
          EXPORTING
            if_algorithm = 'SHA1'
            if_data      = iv_xstring
          IMPORTING
            ef_hashstring = rv_hash ).
      CATCH cx_abap_message_digest.
        rv_hash = '0000000000000000000000000000000000000000'.
    ENDTRY.
  ENDMETHOD.

ENDCLASS.
