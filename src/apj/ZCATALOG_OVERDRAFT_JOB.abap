*&---------------------------------------------------------------------*
*& AJF Job Catalog Registration
*& Run this once in a test program / during transport activation to
*& register the class with the Application Job Catalog (F1240).
*&
*& Transaction: F1240 → "Create Job Catalog Entry"
*&   Job Catalog Entry : ZOVERDRAFT_BATCH
*&   Description       : Overdraft Batch Job
*&   Class Name        : ZCL_BATCH_OVERDRAFT_JOB
*&   Job Template      : ZOVERDRAFT_TEMPLATE  (create via F1240)
*&---------------------------------------------------------------------*

*-- Programmatic registration (alternative to F1240 manual entry) ----
CLASS zcl_apj_catalog_reg DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    CLASS-METHODS register.
ENDCLASS.

CLASS zcl_apj_catalog_reg IMPLEMENTATION.

  METHOD register.

    DATA lo_catalog TYPE REF TO cl_apj_dt_create_content.

    TRY.
        lo_catalog = cl_apj_dt_create_content=>get_instance( ).

        "-- Create catalog entry
        lo_catalog->create_job_cat_entry(
          iv_job_cat_id     = 'ZOVERDRAFT_BATCH'
          iv_job_short_text = 'Overdraft Batch Job'
          iv_class_name     = 'ZCL_BATCH_OVERDRAFT_JOB'
          iv_appl_comp      = 'FIN-FSCM-BCA'          " Adjust to your component
        ).

        "-- Create default job template
        lo_catalog->create_job_template(
          iv_job_cat_id       = 'ZOVERDRAFT_BATCH'
          iv_template_id      = 'ZOVERDRAFT_DEFAULT'
          iv_template_text    = 'Overdraft Job – Default Template'
        ).

        WRITE: / 'AJF catalog entry and template created successfully.'.

      CATCH cx_apj_dt INTO DATA(lx).
        WRITE: / 'Registration failed:', lx->get_text( ).
    ENDTRY.

  ENDMETHOD.

ENDCLASS.


*----------------------------------------------------------------------*
* Notes on external scheduling
* ─────────────────────────────
* 1. F1240 (SAP GUI):
*    - Open F1240, select catalog entry ZOVERDRAFT_BATCH.
*    - Create / copy a job template, fill parameter values, schedule.
*
* 2. External Scheduler (e.g. TWS / Control-M):
*    - Use RFC/BAPI BAPI_XBP_JOB_OPEN + BAPI_XBP_JOB_SUBMIT, or
*    - Fiori App "Application Job Scheduler" via OData API:
*        POST /sap/opu/odata/SAP/APJ_RT_SRV/JobTemplates
*    - Pass variant / parameter values as JSON payload.
*
* 3. Internal API (called from ABAP):
*    DATA lo_rt TYPE REF TO cl_apj_rt.
*    lo_rt = cl_apj_rt=>get_instance( ).
*    lo_rt->schedule_job(
*      iv_job_template_name = 'ZOVERDRAFT_DEFAULT'
*      it_parameters        = lt_params ).
*
* 4. Recurring Jobs:
*    - In F1240 / Fiori Scheduler, set recurrence pattern
*      (daily / weekly / monthly / custom cron expression).
*----------------------------------------------------------------------*
