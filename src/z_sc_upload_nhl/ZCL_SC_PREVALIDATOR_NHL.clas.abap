CLASS zcl_sc_prevalidator_nhl DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    TYPES:
      BEGIN OF ty_validation_error,
        ref_id      TYPE string,
        item_no     TYPE string,
        error_code  TYPE char8,
        error_text  TYPE string,
        sheet       TYPE string,
        excel_row   TYPE i,
      END OF ty_validation_error,
      tt_validation_errors TYPE STANDARD TABLE OF ty_validation_error WITH DEFAULT KEY.

    " Error code constants
    CONSTANTS:
      gc_err_hdr_mandatory   TYPE char8 VALUE 'SCUP_010',
      gc_err_item_mandatory  TYPE char8 VALUE 'SCUP_011',
      gc_err_bill_mandatory  TYPE char8 VALUE 'SCUP_012',
      gc_err_date_format     TYPE char8 VALUE 'SCUP_020',
      gc_err_date_order      TYPE char8 VALUE 'SCUP_021',
      gc_err_numeric         TYPE char8 VALUE 'SCUP_022',
      gc_err_currency        TYPE char8 VALUE 'SCUP_023',
      gc_err_orphan          TYPE char8 VALUE 'SCUP_030',
      gc_err_dup_item        TYPE char8 VALUE 'SCUP_031',
      gc_err_billing_date    TYPE char8 VALUE 'SCUP_032',
      gc_err_bp_not_found    TYPE char8 VALUE 'SCUP_040',
      gc_err_prod_not_found  TYPE char8 VALUE 'SCUP_041'.

    CLASS-METHODS:
      validate
        IMPORTING
          is_parsed        TYPE zcl_sc_xlsx_reader_nhl=>ty_parse_result
        RETURNING
          VALUE(rt_errors) TYPE tt_validation_errors.

  PRIVATE SECTION.

    TYPES:
      tt_char3 TYPE STANDARD TABLE OF char3 WITH DEFAULT KEY.

    CLASS-METHODS:
      check_mandatory_header
        IMPORTING
          is_hdr           TYPE zcl_sc_xlsx_reader_nhl=>ty_header_row
        CHANGING
          ct_errors        TYPE zcl_sc_prevalidator_nhl=>tt_validation_errors,

      check_mandatory_items
        IMPORTING
          it_items         TYPE zcl_sc_xlsx_reader_nhl=>tt_item_rows
          iv_ref_id        TYPE string
        CHANGING
          ct_errors        TYPE zcl_sc_prevalidator_nhl=>tt_validation_errors,

      check_mandatory_billing
        IMPORTING
          it_billing       TYPE zcl_sc_xlsx_reader_nhl=>tt_billing_rows
          iv_ref_id        TYPE string
        CHANGING
          ct_errors        TYPE zcl_sc_prevalidator_nhl=>tt_validation_errors,

      parse_date
        IMPORTING
          iv_date_raw      TYPE string
        RETURNING
          VALUE(rv_date)   TYPE d,

      is_valid_date
        IMPORTING
          iv_date_raw      TYPE string
        RETURNING
          VALUE(rv_valid)  TYPE abap_bool,

      is_numeric
        IMPORTING
          iv_value         TYPE string
        RETURNING
          VALUE(rv_valid)  TYPE abap_bool,

      is_iso_currency
        IMPORTING
          iv_currency      TYPE string
        RETURNING
          VALUE(rv_valid)  TYPE abap_bool,

      check_bp_exists
        IMPORTING
          iv_bp_number     TYPE string
        RETURNING
          VALUE(rv_exists) TYPE abap_bool,

      check_product_exists
        IMPORTING
          iv_product       TYPE string
        RETURNING
          VALUE(rv_exists) TYPE abap_bool,

      add_error
        IMPORTING
          iv_ref_id        TYPE string
          iv_item_no       TYPE string
          iv_code          TYPE char8
          iv_text          TYPE string
          iv_sheet         TYPE string
          iv_row           TYPE i
        CHANGING
          ct_errors        TYPE zcl_sc_prevalidator_nhl=>tt_validation_errors.

ENDCLASS.


CLASS zcl_sc_prevalidator_nhl IMPLEMENTATION.

  METHOD validate.
    " Rules 1–3, 8: per header row checks
    LOOP AT is_parsed-headers INTO DATA(ls_hdr).

      " Rule 1: mandatory header fields
      check_mandatory_header( EXPORTING is_hdr = ls_hdr CHANGING ct_errors = rt_errors ).

      " Rule 4 & 5: date format and order
      IF ls_hdr-start_date_raw IS NOT INITIAL AND is_valid_date( ls_hdr-start_date_raw ) = abap_false.
        add_error(
          EXPORTING iv_ref_id = ls_hdr-ref_id iv_item_no = '' iv_code = gc_err_date_format
                    iv_text = |Invalid date format in Validity Start Date for contract { ls_hdr-ref_id }|
                    iv_sheet = 'Header' iv_row = ls_hdr-excel_row
          CHANGING ct_errors = rt_errors ).
      ENDIF.
      IF ls_hdr-end_date_raw IS NOT INITIAL AND is_valid_date( ls_hdr-end_date_raw ) = abap_false.
        add_error(
          EXPORTING iv_ref_id = ls_hdr-ref_id iv_item_no = '' iv_code = gc_err_date_format
                    iv_text = |Invalid date format in Validity End Date for contract { ls_hdr-ref_id }|
                    iv_sheet = 'Header' iv_row = ls_hdr-excel_row
          CHANGING ct_errors = rt_errors ).
      ENDIF.
      IF is_valid_date( ls_hdr-start_date_raw ) = abap_true AND is_valid_date( ls_hdr-end_date_raw ) = abap_true.
        IF parse_date( ls_hdr-end_date_raw ) <= parse_date( ls_hdr-start_date_raw ).
          add_error(
            EXPORTING iv_ref_id = ls_hdr-ref_id iv_item_no = '' iv_code = gc_err_date_order
                      iv_text = |Contract end date must be after start date for contract { ls_hdr-ref_id }|
                      iv_sheet = 'Header' iv_row = ls_hdr-excel_row
            CHANGING ct_errors = rt_errors ).
        ENDIF.
      ENDIF.

      " Rule 8: at least one item must exist for each header
      DATA(lt_hdr_items) = FILTER #( is_parsed-items USING KEY primary_key
                                     WHERE ref_id = ls_hdr-ref_id ).
      IF lt_hdr_items IS INITIAL.
        add_error(
          EXPORTING iv_ref_id = ls_hdr-ref_id iv_item_no = '' iv_code = gc_err_orphan
                    iv_text = |No items found for contract reference { ls_hdr-ref_id }|
                    iv_sheet = 'Header' iv_row = ls_hdr-excel_row
          CHANGING ct_errors = rt_errors ).
        CONTINUE.
      ENDIF.

      " Rule 2 & 9: item mandatory fields + duplicate item numbers
      check_mandatory_items(
        EXPORTING it_items = lt_hdr_items iv_ref_id = ls_hdr-ref_id
        CHANGING  ct_errors = rt_errors ).

      " Rule 9 extra: check for duplicate item numbers
      DATA lt_item_nos TYPE SORTED TABLE OF string WITH UNIQUE KEY table_line.
      CLEAR lt_item_nos.
      LOOP AT lt_hdr_items INTO DATA(ls_itm).
        IF line_exists( lt_item_nos[ table_line = ls_itm-item_no ] ).
          add_error(
            EXPORTING iv_ref_id = ls_hdr-ref_id iv_item_no = ls_itm-item_no
                      iv_code = gc_err_dup_item
                      iv_text = |Duplicate item number { ls_itm-item_no } in contract { ls_hdr-ref_id }|
                      iv_sheet = 'Item' iv_row = ls_itm-excel_row
            CHANGING ct_errors = rt_errors ).
        ELSE.
          INSERT ls_itm-item_no INTO TABLE lt_item_nos.
        ENDIF.
      ENDLOOP.

      " Rules 3, 10: billing plan mandatory + date within item validity
      LOOP AT lt_hdr_items INTO DATA(ls_item_chk).
        DATA(lt_item_billing) = FILTER #( is_parsed-billing_items
                                          WHERE ref_id = ls_item_chk-ref_id
                                            AND item_no = ls_item_chk-item_no ).

        check_mandatory_billing(
          EXPORTING it_billing = lt_item_billing iv_ref_id = ls_hdr-ref_id
          CHANGING  ct_errors = rt_errors ).

        " Rule 10: billing date within item validity
        IF is_valid_date( ls_item_chk-start_date_raw ) = abap_true
        AND is_valid_date( ls_item_chk-end_date_raw ) = abap_true.
          DATA(lv_item_start) = parse_date( ls_item_chk-start_date_raw ).
          DATA(lv_item_end)   = parse_date( ls_item_chk-end_date_raw ).
          LOOP AT lt_item_billing INTO DATA(ls_bill).
            IF is_valid_date( ls_bill-billing_date_raw ) = abap_true.
              DATA(lv_bill_date) = parse_date( ls_bill-billing_date_raw ).
              IF lv_bill_date < lv_item_start OR lv_bill_date > lv_item_end.
                add_error(
                  EXPORTING iv_ref_id = ls_hdr-ref_id iv_item_no = ls_item_chk-item_no
                            iv_code = gc_err_billing_date
                            iv_text = |Billing date { ls_bill-billing_date_raw } is outside item validity for contract { ls_hdr-ref_id } item { ls_item_chk-item_no }|
                            iv_sheet = 'BillingPlanItem' iv_row = ls_bill-excel_row
                  CHANGING ct_errors = rt_errors ).
              ENDIF.
            ENDIF.
          ENDLOOP.
        ENDIF.
      ENDLOOP.

      " Rule 11 (orphan check): items without headers
      " This is the reverse — items whose ref_id has no header row
      " Handled below after the header loop

      " Rule 40 (BP existence check): check Sold-To party
      IF ls_hdr-sold_to_party IS NOT INITIAL.
        IF check_bp_exists( ls_hdr-sold_to_party ) = abap_false.
          add_error(
            EXPORTING iv_ref_id = ls_hdr-ref_id iv_item_no = '' iv_code = gc_err_bp_not_found
                      iv_text = |Sold-To Party { ls_hdr-sold_to_party } not found for contract { ls_hdr-ref_id }|
                      iv_sheet = 'Header' iv_row = ls_hdr-excel_row
            CHANGING ct_errors = rt_errors ).
        ENDIF.
      ENDIF.

      " Rule 41 (Product existence): check each product
      LOOP AT lt_hdr_items INTO DATA(ls_prd_itm).
        IF ls_prd_itm-product IS NOT INITIAL.
          IF check_product_exists( ls_prd_itm-product ) = abap_false.
            add_error(
              EXPORTING iv_ref_id = ls_hdr-ref_id iv_item_no = ls_prd_itm-item_no
                        iv_code = gc_err_prod_not_found
                        iv_text = |Product { ls_prd_itm-product } not found for contract { ls_hdr-ref_id } item { ls_prd_itm-item_no }|
                        iv_sheet = 'Item' iv_row = ls_prd_itm-excel_row
              CHANGING ct_errors = rt_errors ).
          ENDIF.
        ENDIF.
      ENDLOOP.

    ENDLOOP.

    " Rule 11 (orphan): items with no matching header
    LOOP AT is_parsed-items INTO DATA(ls_orphan_item).
      READ TABLE is_parsed-headers WITH KEY ref_id = ls_orphan_item-ref_id TRANSPORTING NO FIELDS.
      IF sy-subrc <> 0.
        add_error(
          EXPORTING iv_ref_id = ls_orphan_item-ref_id iv_item_no = ls_orphan_item-item_no
                    iv_code = gc_err_orphan
                    iv_text = |Orphan item record: no header found for reference { ls_orphan_item-ref_id }|
                    iv_sheet = 'Item' iv_row = ls_orphan_item-excel_row
          CHANGING ct_errors = rt_errors ).
      ENDIF.
    ENDLOOP.

    " Rule 11 (orphan): billing rows with no matching item
    LOOP AT is_parsed-billing_items INTO DATA(ls_orphan_bill).
      READ TABLE is_parsed-items WITH KEY ref_id = ls_orphan_bill-ref_id item_no = ls_orphan_bill-item_no TRANSPORTING NO FIELDS.
      IF sy-subrc <> 0.
        add_error(
          EXPORTING iv_ref_id = ls_orphan_bill-ref_id iv_item_no = ls_orphan_bill-item_no
                    iv_code = gc_err_orphan
                    iv_text = |Orphan billing row: no item { ls_orphan_bill-item_no } found for reference { ls_orphan_bill-ref_id }|
                    iv_sheet = 'BillingPlanItem' iv_row = ls_orphan_bill-excel_row
          CHANGING ct_errors = rt_errors ).
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD check_mandatory_header.
    IF is_hdr-service_contract_type IS INITIAL.
      add_error( EXPORTING iv_ref_id = is_hdr-ref_id iv_item_no = '' iv_code = gc_err_hdr_mandatory
                           iv_text = |Mandatory field Contract Type missing for { is_hdr-ref_id }|
                           iv_sheet = 'Header' iv_row = is_hdr-excel_row CHANGING ct_errors = ct_errors ).
    ENDIF.
    IF is_hdr-sold_to_party IS INITIAL.
      add_error( EXPORTING iv_ref_id = is_hdr-ref_id iv_item_no = '' iv_code = gc_err_hdr_mandatory
                           iv_text = |Mandatory field Customer Number missing for { is_hdr-ref_id }|
                           iv_sheet = 'Header' iv_row = is_hdr-excel_row CHANGING ct_errors = ct_errors ).
    ENDIF.
    IF is_hdr-start_date_raw IS INITIAL.
      add_error( EXPORTING iv_ref_id = is_hdr-ref_id iv_item_no = '' iv_code = gc_err_hdr_mandatory
                           iv_text = |Mandatory field Validity Start Date missing for { is_hdr-ref_id }|
                           iv_sheet = 'Header' iv_row = is_hdr-excel_row CHANGING ct_errors = ct_errors ).
    ENDIF.
    IF is_hdr-end_date_raw IS INITIAL.
      add_error( EXPORTING iv_ref_id = is_hdr-ref_id iv_item_no = '' iv_code = gc_err_hdr_mandatory
                           iv_text = |Mandatory field Validity End Date missing for { is_hdr-ref_id }|
                           iv_sheet = 'Header' iv_row = is_hdr-excel_row CHANGING ct_errors = ct_errors ).
    ENDIF.
    IF is_hdr-sales_org IS INITIAL.
      add_error( EXPORTING iv_ref_id = is_hdr-ref_id iv_item_no = '' iv_code = gc_err_hdr_mandatory
                           iv_text = |Mandatory field Sales Organization missing for { is_hdr-ref_id }|
                           iv_sheet = 'Header' iv_row = is_hdr-excel_row CHANGING ct_errors = ct_errors ).
    ENDIF.
    IF is_hdr-dist_channel IS INITIAL.
      add_error( EXPORTING iv_ref_id = is_hdr-ref_id iv_item_no = '' iv_code = gc_err_hdr_mandatory
                           iv_text = |Mandatory field Distribution Channel missing for { is_hdr-ref_id }|
                           iv_sheet = 'Header' iv_row = is_hdr-excel_row CHANGING ct_errors = ct_errors ).
    ENDIF.
    IF is_hdr-division IS INITIAL.
      add_error( EXPORTING iv_ref_id = is_hdr-ref_id iv_item_no = '' iv_code = gc_err_hdr_mandatory
                           iv_text = |Mandatory field Division missing for { is_hdr-ref_id }|
                           iv_sheet = 'Header' iv_row = is_hdr-excel_row CHANGING ct_errors = ct_errors ).
    ENDIF.
    " UPDATE requires existing contract number
    IF is_hdr-control_field = 'UPDATE' AND is_hdr-service_contract IS INITIAL.
      add_error( EXPORTING iv_ref_id = is_hdr-ref_id iv_item_no = '' iv_code = gc_err_hdr_mandatory
                           iv_text = |Existing Service Contract Number required for UPDATE action in { is_hdr-ref_id }|
                           iv_sheet = 'Header' iv_row = is_hdr-excel_row CHANGING ct_errors = ct_errors ).
    ENDIF.
  ENDMETHOD.


  METHOD check_mandatory_items.
    LOOP AT it_items INTO DATA(ls_item).
      IF ls_item-item_no IS INITIAL.
        add_error( EXPORTING iv_ref_id = iv_ref_id iv_item_no = '' iv_code = gc_err_item_mandatory
                             iv_text = |Mandatory field Item Number missing for { iv_ref_id }|
                             iv_sheet = 'Item' iv_row = ls_item-excel_row CHANGING ct_errors = ct_errors ).
      ENDIF.
      IF ls_item-product IS INITIAL.
        add_error( EXPORTING iv_ref_id = iv_ref_id iv_item_no = ls_item-item_no
                             iv_code = gc_err_item_mandatory
                             iv_text = |Mandatory field Product missing for { iv_ref_id } item { ls_item-item_no }|
                             iv_sheet = 'Item' iv_row = ls_item-excel_row CHANGING ct_errors = ct_errors ).
      ENDIF.
      " Validate numeric fields if present
      IF ls_item-order_qty_raw IS NOT INITIAL AND is_numeric( ls_item-order_qty_raw ) = abap_false.
        add_error( EXPORTING iv_ref_id = iv_ref_id iv_item_no = ls_item-item_no
                             iv_code = gc_err_numeric
                             iv_text = |Invalid numeric value in Quantity for { iv_ref_id } item { ls_item-item_no }|
                             iv_sheet = 'Item' iv_row = ls_item-excel_row CHANGING ct_errors = ct_errors ).
      ENDIF.
      IF ls_item-net_amount_raw IS NOT INITIAL AND is_numeric( ls_item-net_amount_raw ) = abap_false.
        add_error( EXPORTING iv_ref_id = iv_ref_id iv_item_no = ls_item-item_no
                             iv_code = gc_err_numeric
                             iv_text = |Invalid numeric value in Net Amount for { iv_ref_id } item { ls_item-item_no }|
                             iv_sheet = 'Item' iv_row = ls_item-excel_row CHANGING ct_errors = ct_errors ).
      ENDIF.
      IF ls_item-currency IS NOT INITIAL AND is_iso_currency( ls_item-currency ) = abap_false.
        add_error( EXPORTING iv_ref_id = iv_ref_id iv_item_no = ls_item-item_no
                             iv_code = gc_err_currency
                             iv_text = |Invalid currency code { ls_item-currency } for { iv_ref_id } item { ls_item-item_no }|
                             iv_sheet = 'Item' iv_row = ls_item-excel_row CHANGING ct_errors = ct_errors ).
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD check_mandatory_billing.
    LOOP AT it_billing INTO DATA(ls_bill).
      IF ls_bill-billing_date_raw IS INITIAL.
        add_error( EXPORTING iv_ref_id = iv_ref_id iv_item_no = ls_bill-item_no
                             iv_code = gc_err_bill_mandatory
                             iv_text = |Mandatory field Billing Date missing for { iv_ref_id } item { ls_bill-item_no }|
                             iv_sheet = 'BillingPlanItem' iv_row = ls_bill-excel_row CHANGING ct_errors = ct_errors ).
      ELSEIF is_valid_date( ls_bill-billing_date_raw ) = abap_false.
        add_error( EXPORTING iv_ref_id = iv_ref_id iv_item_no = ls_bill-item_no
                             iv_code = gc_err_date_format
                             iv_text = |Invalid date format in Billing Date for { iv_ref_id } item { ls_bill-item_no }|
                             iv_sheet = 'BillingPlanItem' iv_row = ls_bill-excel_row CHANGING ct_errors = ct_errors ).
      ENDIF.
      IF ls_bill-amount_raw IS INITIAL.
        add_error( EXPORTING iv_ref_id = iv_ref_id iv_item_no = ls_bill-item_no
                             iv_code = gc_err_bill_mandatory
                             iv_text = |Mandatory field Billing Amount missing for { iv_ref_id } item { ls_bill-item_no }|
                             iv_sheet = 'BillingPlanItem' iv_row = ls_bill-excel_row CHANGING ct_errors = ct_errors ).
      ELSEIF is_numeric( ls_bill-amount_raw ) = abap_false.
        add_error( EXPORTING iv_ref_id = iv_ref_id iv_item_no = ls_bill-item_no
                             iv_code = gc_err_numeric
                             iv_text = |Invalid numeric value in Billing Amount for { iv_ref_id } item { ls_bill-item_no }|
                             iv_sheet = 'BillingPlanItem' iv_row = ls_bill-excel_row CHANGING ct_errors = ct_errors ).
      ENDIF.
      IF ls_bill-currency IS INITIAL.
        add_error( EXPORTING iv_ref_id = iv_ref_id iv_item_no = ls_bill-item_no
                             iv_code = gc_err_bill_mandatory
                             iv_text = |Mandatory field Currency missing in Billing Plan for { iv_ref_id } item { ls_bill-item_no }|
                             iv_sheet = 'BillingPlanItem' iv_row = ls_bill-excel_row CHANGING ct_errors = ct_errors ).
      ELSEIF is_iso_currency( ls_bill-currency ) = abap_false.
        add_error( EXPORTING iv_ref_id = iv_ref_id iv_item_no = ls_bill-item_no
                             iv_code = gc_err_currency
                             iv_text = |Invalid currency code { ls_bill-currency } in Billing Plan for { iv_ref_id }|
                             iv_sheet = 'BillingPlanItem' iv_row = ls_bill-excel_row CHANGING ct_errors = ct_errors ).
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD is_valid_date.
    " Accepts DD/MM/YYYY format
    rv_valid = abap_false.
    CHECK strlen( iv_date_raw ) = 10.
    CHECK iv_date_raw+2(1) = '/' AND iv_date_raw+5(1) = '/'.
    DATA(lv_day)  = CONV i( iv_date_raw(2) ).
    DATA(lv_mon)  = CONV i( iv_date_raw+3(2) ).
    DATA(lv_year) = CONV i( iv_date_raw+6(4) ).
    CHECK lv_day BETWEEN 1 AND 31 AND lv_mon BETWEEN 1 AND 12 AND lv_year BETWEEN 1900 AND 9999.
    rv_valid = abap_true.
  ENDMETHOD.


  METHOD parse_date.
    " Convert DD/MM/YYYY to ABAP date YYYYMMDD
    CHECK is_valid_date( iv_date_raw ) = abap_true.
    rv_date = |{ iv_date_raw+6(4) }{ iv_date_raw+3(2) }{ iv_date_raw(2) }|.
  ENDMETHOD.


  METHOD is_numeric.
    " Accepts integers and decimals (with . or ,)
    rv_valid = abap_false.
    CHECK iv_value IS NOT INITIAL.
    DATA(lv_clean) = replace( val = iv_value sub = ',' with = '.' occ = 0 ).
    DATA lv_dummy TYPE decfloat34.
    TRY.
        lv_dummy = lv_clean.
        rv_valid = abap_true.
      CATCH cx_sy_conversion_error cx_sy_arithmetic_error.
        rv_valid = abap_false.
    ENDTRY.
  ENDMETHOD.


  METHOD is_iso_currency.
    rv_valid = abap_false.
    CHECK strlen( iv_currency ) = 3.
    " Simple structural check: 3 uppercase alpha characters
    DATA(lv_upper) = to_upper( iv_currency ).
    FIND REGEX '^[A-Z]{3}$' IN lv_upper.
    rv_valid = COND #( WHEN sy-subrc = 0 THEN abap_true ELSE abap_false ).
  ENDMETHOD.


  METHOD check_bp_exists.
    SELECT SINGLE businesspartner FROM i_businesspartner
      WHERE businesspartner = @iv_bp_number
      INTO @DATA(lv_bp).
    rv_exists = COND #( WHEN sy-subrc = 0 THEN abap_true ELSE abap_false ).
  ENDMETHOD.


  METHOD check_product_exists.
    SELECT SINGLE product FROM i_product
      WHERE product = @iv_product
      INTO @DATA(lv_prod).
    rv_exists = COND #( WHEN sy-subrc = 0 THEN abap_true ELSE abap_false ).
  ENDMETHOD.


  METHOD add_error.
    APPEND VALUE #(
      ref_id     = iv_ref_id
      item_no    = iv_item_no
      error_code = iv_code
      error_text = iv_text
      sheet      = iv_sheet
      excel_row  = iv_row
    ) TO ct_errors.
  ENDMETHOD.

ENDCLASS.
