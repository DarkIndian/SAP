CLASS zbp_i_sc_upload_run_nhl DEFINITION
  PUBLIC
  ABSTRACT
  FINAL
  FOR BEHAVIOR OF zi_sc_upload_run_nhl.

  PRIVATE SECTION.

    METHODS:
      get_instance_authorizations FOR INSTANCE AUTHORIZATION
        IMPORTING keys REQUEST requested_authorizations FOR UploadRun
        RESULT result,

      uploadexcel FOR ACTION
        IMPORTING keys FOR UploadRun~uploadExcel
        RESULT result,

      reprocessfailed FOR ACTION
        IMPORTING keys FOR UploadRun~reprocessFailed
        RESULT result,

      save_modified FOR ADDITIONAL SAVE.

ENDCLASS.


CLASS zbp_i_sc_upload_run_nhl IMPLEMENTATION.

  METHOD get_instance_authorizations.
    LOOP AT keys INTO DATA(ls_key).
      APPEND VALUE #(
        %tky                           = ls_key-%tky
        %action-uploadExcel            = if_abap_behv=>auth-allowed
        %action-reprocessFailed        = if_abap_behv=>auth-allowed
      ) TO result.
    ENDLOOP.
  ENDMETHOD.


  METHOD uploadexcel.
    " Read the parameter passed with the action
    READ ENTITIES OF zi_sc_upload_run_nhl IN LOCAL MODE
      ENTITY UploadRun
        FIELDS ( FileName OverallStatus )
      WITH CORRESPONDING #( keys )
      RESULT DATA(lt_runs)
      FAILED DATA(lt_failed).

    LOOP AT keys INTO DATA(ls_key).
      " Find the matching run entity
      READ TABLE lt_runs INTO DATA(ls_run)
        WITH KEY %tky = ls_key-%tky.
      IF sy-subrc <> 0. CONTINUE. ENDIF.

      " Update status to RUNNING
      MODIFY ENTITIES OF zi_sc_upload_run_nhl IN LOCAL MODE
        ENTITY UploadRun
          UPDATE FIELDS ( OverallStatus UploadTimestamp UploadedBy )
          WITH VALUE #( (
            %tky            = ls_key-%tky
            OverallStatus   = 'RUNNING'
            UploadTimestamp = cl_abap_context_info=>get_system_date( ) && cl_abap_context_info=>get_system_time( )
            UploadedBy      = cl_abap_context_info=>get_user_alias( )
          ) )
        REPORTED DATA(lt_update_reported).

      " Delegate processing to orchestrator
      TRY.
          DATA(lo_orch) = NEW zcl_sc_upload_orch_nhl( ).
          DATA(ls_result) = lo_orch->process_upload(
            iv_run_uuid    = ls_key-UploadRunUuid
            iv_file_content = ls_key-%param-FileContent
            iv_file_name   = ls_key-%param-FileName ).

          " Update run with final counts and status
          MODIFY ENTITIES OF zi_sc_upload_run_nhl IN LOCAL MODE
            ENTITY UploadRun
              UPDATE FIELDS ( OverallStatus TotalRecords SuccessCount FailedCount
                              FileHash FileSizeBytes BaliLogHandle )
              WITH VALUE #( (
                %tky           = ls_key-%tky
                OverallStatus  = ls_result-overall_status
                TotalRecords   = ls_result-total_records
                SuccessCount   = ls_result-success_count
                FailedCount    = ls_result-failed_count
                FileHash       = ls_result-file_hash
                FileSizeBytes  = ls_result-file_size_bytes
                BaliLogHandle  = ls_result-bali_log_handle
              ) )
            REPORTED DATA(lt_final_reported).

        CATCH cx_root INTO DATA(lx_root).
          MODIFY ENTITIES OF zi_sc_upload_run_nhl IN LOCAL MODE
            ENTITY UploadRun
              UPDATE FIELDS ( OverallStatus )
              WITH VALUE #( (
                %tky          = ls_key-%tky
                OverallStatus = 'FAILED'
              ) )
            REPORTED DATA(lt_err_reported).

          APPEND VALUE #(
            %tky        = ls_key-%tky
            %msg        = NEW /dmo/cx_rap_model_provider_err(
                            textid = /dmo/cx_rap_model_provider_err=>provider_err )
          ) TO reported-UploadRun.
      ENDTRY.

      " Return updated entity
      READ ENTITIES OF zi_sc_upload_run_nhl IN LOCAL MODE
        ENTITY UploadRun ALL FIELDS
        WITH VALUE #( ( %tky = ls_key-%tky ) )
        RESULT DATA(lt_updated).

      APPEND VALUE #(
        %tky   = ls_key-%tky
        %param = ls_updated
      ) TO result.
    ENDLOOP.
  ENDMETHOD.


  METHOD reprocessfailed.
    " Re-run only the FAILED records from a previous run
    " Reads the existing result rows with ERROR status and resubmits via orchestrator
    LOOP AT keys INTO DATA(ls_key).
      TRY.
          DATA(lo_orch) = NEW zcl_sc_upload_orch_nhl( ).
          lo_orch->reprocess_failed( iv_run_uuid = ls_key-UploadRunUuid ).
        CATCH cx_root.
          " Errors surfaced via the result table; action does not raise RAP messages
      ENDTRY.

      READ ENTITIES OF zi_sc_upload_run_nhl IN LOCAL MODE
        ENTITY UploadRun ALL FIELDS
        WITH VALUE #( ( %tky = ls_key-%tky ) )
        RESULT DATA(lt_updated).

      LOOP AT lt_updated INTO DATA(ls_updated).
        APPEND VALUE #(
          %tky   = ls_key-%tky
          %param = ls_updated
        ) TO result.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.


  METHOD save_modified.
    " Additional save hook — write result rows inserted by orchestrator
    " into ZSC_UPLOAD_RES_NHL via direct INSERT (orchestrator buffers them).
    " The orchestrator handles DB persistence itself; this method is a no-op
    " unless the framework requires explicit commit coordination.
    IF create-UploadRun IS NOT INITIAL.
      LOOP AT create-UploadRun INTO DATA(ls_create).
        " Initialise audit fields on new run rows
        DATA(lv_now) = cl_abap_context_info=>get_system_date( )
                       && cl_abap_context_info=>get_system_time( ).
        UPDATE zsc_upload_run_nhl
          SET created_by      = @( cl_abap_context_info=>get_user_alias( ) )
              created_at      = @lv_now
              last_changed_by = @( cl_abap_context_info=>get_user_alias( ) )
              last_changed_at = @lv_now
          WHERE upload_run_uuid = @ls_create-UploadRunUuid.
      ENDLOOP.
    ENDIF.
  ENDMETHOD.

ENDCLASS.
