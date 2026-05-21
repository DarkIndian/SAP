CLASS zcl_sc_xlsx_reader_nhl DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    TYPES:
      "-- Header row (semantic)
      BEGIN OF ty_header_row,
        ref_id                    TYPE string,
        control_field             TYPE string,
        service_contract          TYPE string,
        service_contract_type     TYPE string,
        sold_to_party             TYPE string,
        service_doc_desc          TYPE string,
        start_date_raw            TYPE string,
        end_date_raw              TYPE string,
        contact_person            TYPE string,
        employee_responsible      TYPE string,
        sales_org                 TYPE string,
        dist_channel              TYPE string,
        division                  TYPE string,
        req_start_date_raw        TYPE string,
        signature_date_raw        TYPE string,
        yy1_billing_summary_ind   TYPE string,
        yy1_billing_description   TYPE string,
        yy1_billing_header_terri  TYPE string,
        yy1_billing_header_autom  TYPE string,
        yy1_billing_item_summary  TYPE string,
        yy1_billing_header_categ  TYPE string,
        yy1_billing_header_dateo  TYPE string,
        yy1_billing_header_early  TYPE string,
        yy1_billing_header_initia TYPE string,
        yy1_billing_header_negot  TYPE string,
        yy1_billing_header_optio  TYPE string,
        yy1_override_billing_ite  TYPE string,
        yy1_billing_header_renew  TYPE string,
        yy1_billing_header_subca  TYPE string,
        wbs_element               TYPE string,
        excel_row                 TYPE i,
      END OF ty_header_row,
      tt_header_rows TYPE SORTED TABLE OF ty_header_row WITH UNIQUE KEY ref_id,

      "-- Item row (semantic)
      BEGIN OF ty_item_row,
        ref_id               TYPE string,
        item_no              TYPE string,
        product              TYPE string,
        item_desc            TYPE string,
        start_date_raw       TYPE string,
        end_date_raw         TYPE string,
        wbs_element          TYPE string,
        order_qty_raw        TYPE string,
        order_qty_unit       TYPE string,
        net_amount_raw       TYPE string,
        currency             TYPE string,
        yy1_recv_comp_code   TYPE string,
        yy1_recv_profit_center TYPE string,
        excel_row            TYPE i,
      END OF ty_item_row,
      tt_item_rows TYPE SORTED TABLE OF ty_item_row WITH NON-UNIQUE KEY ref_id item_no,

      "-- Billing plan item row
      BEGIN OF ty_billing_row,
        ref_id          TYPE string,
        item_no         TYPE string,
        billing_date_raw TYPE string,
        amount_raw      TYPE string,
        currency        TYPE string,
        excel_row       TYPE i,
      END OF ty_billing_row,
      tt_billing_rows TYPE STANDARD TABLE OF ty_billing_row WITH DEFAULT KEY,

      "-- Partner row
      BEGIN OF ty_partner_row,
        ref_id           TYPE string,
        item_no          TYPE string,
        partner_function TYPE string,
        business_partner TYPE string,
        excel_row        TYPE i,
      END OF ty_partner_row,
      tt_partner_rows TYPE STANDARD TABLE OF ty_partner_row WITH DEFAULT KEY,

      "-- Sales employee row
      BEGIN OF ty_salesempl_row,
        ref_id           TYPE string,
        employee_number  TYPE string,
        partner_function TYPE string,
        excel_row        TYPE i,
      END OF ty_salesempl_row,
      tt_salesempl_rows TYPE STANDARD TABLE OF ty_salesempl_row WITH DEFAULT KEY,

      "-- Complete parsed result
      BEGIN OF ty_parse_result,
        headers       TYPE tt_header_rows,
        items         TYPE tt_item_rows,
        billing_items TYPE tt_billing_rows,
        partners      TYPE tt_partner_rows,
        sales_empls   TYPE tt_salesempl_rows,
      END OF ty_parse_result.

    CLASS-METHODS:
      parse
        IMPORTING
          iv_file_content  TYPE xstring
        RETURNING
          VALUE(rs_result) TYPE ty_parse_result
        RAISING
          cx_sy_conversion_error.

  PRIVATE SECTION.

    CONSTANTS:
      gc_sheet_header      TYPE string VALUE 'Header',
      gc_sheet_item        TYPE string VALUE 'Item',
      gc_sheet_billing     TYPE string VALUE 'BillingPlanItem',
      gc_sheet_partner     TYPE string VALUE 'Partner',
      gc_sheet_sales_empl  TYPE string VALUE 'SalesEmployee'.

    CLASS-METHODS:
      read_sheet_rows
        IMPORTING
          io_worksheet     TYPE REF TO if_xco_xlsx_worksheet
        RETURNING
          VALUE(rt_rows)   TYPE string_table,

      sheet_exists
        IMPORTING
          io_workbook      TYPE REF TO if_xco_xlsx_workbook
          iv_name          TYPE string
        RETURNING
          VALUE(rv_exists) TYPE abap_bool,

      get_cell_value
        IMPORTING
          io_row           TYPE REF TO if_xco_xlsx_read_access_row
          iv_col           TYPE i
        RETURNING
          VALUE(rv_value)  TYPE string,

      parse_header_sheet
        IMPORTING
          io_workbook      TYPE REF TO if_xco_xlsx_workbook
        RETURNING
          VALUE(rt_headers) TYPE tt_header_rows,

      parse_item_sheet
        IMPORTING
          io_workbook      TYPE REF TO if_xco_xlsx_workbook
        RETURNING
          VALUE(rt_items)  TYPE tt_item_rows,

      parse_billing_sheet
        IMPORTING
          io_workbook      TYPE REF TO if_xco_xlsx_workbook
        RETURNING
          VALUE(rt_billing) TYPE tt_billing_rows,

      parse_partner_sheet
        IMPORTING
          io_workbook      TYPE REF TO if_xco_xlsx_workbook
        RETURNING
          VALUE(rt_partners) TYPE tt_partner_rows,

      parse_salesempl_sheet
        IMPORTING
          io_workbook      TYPE REF TO if_xco_xlsx_workbook
        RETURNING
          VALUE(rt_empls)  TYPE tt_salesempl_rows.

ENDCLASS.


CLASS zcl_sc_xlsx_reader_nhl IMPLEMENTATION.

  METHOD parse.
    CHECK iv_file_content IS NOT INITIAL.

    DATA(lo_doc)  = xco_cp_xlsx=>document->for_file_contents( iv_file_content ).
    DATA(lo_wb)   = lo_doc->workbook( ).

    " Validate that required sheets exist
    IF sheet_exists( io_workbook = lo_wb iv_name = gc_sheet_header ) = abap_false
    OR sheet_exists( io_workbook = lo_wb iv_name = gc_sheet_item )   = abap_false.
      RAISE EXCEPTION TYPE cx_sy_conversion_error.
    ENDIF.

    rs_result-headers      = parse_header_sheet(  lo_wb ).
    rs_result-items        = parse_item_sheet(    lo_wb ).
    rs_result-billing_items = parse_billing_sheet( lo_wb ).

    IF sheet_exists( io_workbook = lo_wb iv_name = gc_sheet_partner ) = abap_true.
      rs_result-partners  = parse_partner_sheet(   lo_wb ).
    ENDIF.
    IF sheet_exists( io_workbook = lo_wb iv_name = gc_sheet_sales_empl ) = abap_true.
      rs_result-sales_empls = parse_salesempl_sheet( lo_wb ).
    ENDIF.
  ENDMETHOD.


  METHOD sheet_exists.
    rv_exists = lo_workbook->worksheet->has_worksheet_at_name( iv_name ).
  ENDMETHOD.


  METHOD get_cell_value.
    TRY.
        DATA(lo_cell) = io_row->get_cell( xco_cp_xlsx_cell_coordinate=>for( iv_x = iv_col iv_y = 1 ) ).
        rv_value = COND #( WHEN lo_cell IS BOUND
                           THEN condense( lo_cell->get_value( )->get_formatted( ) ) ).
      CATCH cx_root.
        rv_value = ''.
    ENDTRY.
  ENDMETHOD.


  METHOD parse_header_sheet.
    DATA(lo_ws) = lo_workbook->worksheet->at_name( gc_sheet_header ).
    DATA(lo_sel) = lo_ws->select( xco_cp_xlsx_selection=>factory->new_row_range(
      xco_cp_xlsx_cell_coordinate=>for( iv_x = 1 iv_y = 2 )
      xco_cp_xlsx_cell_coordinate=>for( iv_x = 30 iv_y = 10000 ) ) ).

    DATA(lo_cursor) = lo_sel->row_stream( )->get_cursor( ).
    DATA lv_row_num TYPE i VALUE 1.

    WHILE lo_cursor->advance( ) = abap_true.
      ADD 1 TO lv_row_num.
      DATA(lo_row) = lo_cursor->get_current_row( ).

      DATA(lv_ref_id) = get_cell_value( io_row = lo_row iv_col = 1 ).
      IF lv_ref_id IS INITIAL. CONTINUE. ENDIF.   " skip empty rows

      APPEND VALUE #(
        ref_id                    = lv_ref_id
        control_field             = get_cell_value( io_row = lo_row iv_col = 2  )
        service_contract          = get_cell_value( io_row = lo_row iv_col = 3  )
        service_contract_type     = get_cell_value( io_row = lo_row iv_col = 4  )
        sold_to_party             = get_cell_value( io_row = lo_row iv_col = 5  )
        service_doc_desc          = get_cell_value( io_row = lo_row iv_col = 6  )
        start_date_raw            = get_cell_value( io_row = lo_row iv_col = 7  )
        end_date_raw              = get_cell_value( io_row = lo_row iv_col = 8  )
        contact_person            = get_cell_value( io_row = lo_row iv_col = 9  )
        employee_responsible      = get_cell_value( io_row = lo_row iv_col = 10 )
        sales_org                 = get_cell_value( io_row = lo_row iv_col = 11 )
        dist_channel              = get_cell_value( io_row = lo_row iv_col = 12 )
        division                  = get_cell_value( io_row = lo_row iv_col = 13 )
        req_start_date_raw        = get_cell_value( io_row = lo_row iv_col = 14 )
        signature_date_raw        = get_cell_value( io_row = lo_row iv_col = 15 )
        yy1_billing_summary_ind   = get_cell_value( io_row = lo_row iv_col = 16 )
        yy1_billing_description   = get_cell_value( io_row = lo_row iv_col = 17 )
        yy1_billing_header_terri  = get_cell_value( io_row = lo_row iv_col = 18 )
        yy1_billing_header_autom  = get_cell_value( io_row = lo_row iv_col = 19 )
        yy1_billing_item_summary  = get_cell_value( io_row = lo_row iv_col = 20 )
        yy1_billing_header_categ  = get_cell_value( io_row = lo_row iv_col = 21 )
        yy1_billing_header_dateo  = get_cell_value( io_row = lo_row iv_col = 22 )
        yy1_billing_header_early  = get_cell_value( io_row = lo_row iv_col = 23 )
        yy1_billing_header_initia = get_cell_value( io_row = lo_row iv_col = 24 )
        yy1_billing_header_negot  = get_cell_value( io_row = lo_row iv_col = 25 )
        yy1_billing_header_optio  = get_cell_value( io_row = lo_row iv_col = 26 )
        yy1_override_billing_ite  = get_cell_value( io_row = lo_row iv_col = 27 )
        yy1_billing_header_renew  = get_cell_value( io_row = lo_row iv_col = 28 )
        yy1_billing_header_subca  = get_cell_value( io_row = lo_row iv_col = 29 )
        wbs_element               = get_cell_value( io_row = lo_row iv_col = 30 )
        excel_row                 = lv_row_num
      ) TO rt_headers.
    ENDWHILE.
  ENDMETHOD.


  METHOD parse_item_sheet.
    DATA(lo_ws) = lo_workbook->worksheet->at_name( gc_sheet_item ).
    DATA(lo_sel) = lo_ws->select( xco_cp_xlsx_selection=>factory->new_row_range(
      xco_cp_xlsx_cell_coordinate=>for( iv_x = 1 iv_y = 2 )
      xco_cp_xlsx_cell_coordinate=>for( iv_x = 13 iv_y = 10000 ) ) ).

    DATA(lo_cursor) = lo_sel->row_stream( )->get_cursor( ).
    DATA lv_row_num TYPE i VALUE 1.

    WHILE lo_cursor->advance( ) = abap_true.
      ADD 1 TO lv_row_num.
      DATA(lo_row) = lo_cursor->get_current_row( ).
      DATA(lv_ref_id) = get_cell_value( io_row = lo_row iv_col = 1 ).
      IF lv_ref_id IS INITIAL. CONTINUE. ENDIF.

      APPEND VALUE #(
        ref_id               = lv_ref_id
        item_no              = get_cell_value( io_row = lo_row iv_col = 2  )
        product              = get_cell_value( io_row = lo_row iv_col = 3  )
        item_desc            = get_cell_value( io_row = lo_row iv_col = 4  )
        start_date_raw       = get_cell_value( io_row = lo_row iv_col = 5  )
        end_date_raw         = get_cell_value( io_row = lo_row iv_col = 6  )
        wbs_element          = get_cell_value( io_row = lo_row iv_col = 7  )
        order_qty_raw        = get_cell_value( io_row = lo_row iv_col = 8  )
        order_qty_unit       = get_cell_value( io_row = lo_row iv_col = 9  )
        net_amount_raw       = get_cell_value( io_row = lo_row iv_col = 10 )
        currency             = get_cell_value( io_row = lo_row iv_col = 11 )
        yy1_recv_comp_code   = get_cell_value( io_row = lo_row iv_col = 12 )
        yy1_recv_profit_center = get_cell_value( io_row = lo_row iv_col = 13 )
        excel_row            = lv_row_num
      ) TO rt_items.
    ENDWHILE.
  ENDMETHOD.


  METHOD parse_billing_sheet.
    DATA(lo_ws) = lo_workbook->worksheet->at_name( gc_sheet_billing ).
    DATA(lo_sel) = lo_ws->select( xco_cp_xlsx_selection=>factory->new_row_range(
      xco_cp_xlsx_cell_coordinate=>for( iv_x = 1 iv_y = 2 )
      xco_cp_xlsx_cell_coordinate=>for( iv_x = 5 iv_y = 10000 ) ) ).

    DATA(lo_cursor) = lo_sel->row_stream( )->get_cursor( ).
    DATA lv_row_num TYPE i VALUE 1.

    WHILE lo_cursor->advance( ) = abap_true.
      ADD 1 TO lv_row_num.
      DATA(lo_row) = lo_cursor->get_current_row( ).
      DATA(lv_ref_id) = get_cell_value( io_row = lo_row iv_col = 1 ).
      IF lv_ref_id IS INITIAL. CONTINUE. ENDIF.

      APPEND VALUE #(
        ref_id          = lv_ref_id
        item_no         = get_cell_value( io_row = lo_row iv_col = 2 )
        billing_date_raw = get_cell_value( io_row = lo_row iv_col = 3 )
        amount_raw      = get_cell_value( io_row = lo_row iv_col = 4 )
        currency        = get_cell_value( io_row = lo_row iv_col = 5 )
        excel_row       = lv_row_num
      ) TO rt_billing.
    ENDWHILE.
  ENDMETHOD.


  METHOD parse_partner_sheet.
    DATA(lo_ws) = lo_workbook->worksheet->at_name( gc_sheet_partner ).
    DATA(lo_sel) = lo_ws->select( xco_cp_xlsx_selection=>factory->new_row_range(
      xco_cp_xlsx_cell_coordinate=>for( iv_x = 1 iv_y = 2 )
      xco_cp_xlsx_cell_coordinate=>for( iv_x = 4 iv_y = 10000 ) ) ).

    DATA(lo_cursor) = lo_sel->row_stream( )->get_cursor( ).
    DATA lv_row_num TYPE i VALUE 1.

    WHILE lo_cursor->advance( ) = abap_true.
      ADD 1 TO lv_row_num.
      DATA(lo_row) = lo_cursor->get_current_row( ).
      DATA(lv_ref_id) = get_cell_value( io_row = lo_row iv_col = 1 ).
      IF lv_ref_id IS INITIAL. CONTINUE. ENDIF.

      APPEND VALUE #(
        ref_id           = lv_ref_id
        item_no          = get_cell_value( io_row = lo_row iv_col = 2 )
        partner_function = get_cell_value( io_row = lo_row iv_col = 3 )
        business_partner = get_cell_value( io_row = lo_row iv_col = 4 )
        excel_row        = lv_row_num
      ) TO rt_partners.
    ENDWHILE.
  ENDMETHOD.


  METHOD parse_salesempl_sheet.
    DATA(lo_ws) = lo_workbook->worksheet->at_name( gc_sheet_sales_empl ).
    DATA(lo_sel) = lo_ws->select( xco_cp_xlsx_selection=>factory->new_row_range(
      xco_cp_xlsx_cell_coordinate=>for( iv_x = 1 iv_y = 2 )
      xco_cp_xlsx_cell_coordinate=>for( iv_x = 3 iv_y = 10000 ) ) ).

    DATA(lo_cursor) = lo_sel->row_stream( )->get_cursor( ).
    DATA lv_row_num TYPE i VALUE 1.

    WHILE lo_cursor->advance( ) = abap_true.
      ADD 1 TO lv_row_num.
      DATA(lo_row) = lo_cursor->get_current_row( ).
      DATA(lv_ref_id) = get_cell_value( io_row = lo_row iv_col = 1 ).
      IF lv_ref_id IS INITIAL. CONTINUE. ENDIF.

      APPEND VALUE #(
        ref_id           = lv_ref_id
        employee_number  = get_cell_value( io_row = lo_row iv_col = 2 )
        partner_function = get_cell_value( io_row = lo_row iv_col = 3 )
        excel_row        = lv_row_num
      ) TO rt_empls.
    ENDWHILE.
  ENDMETHOD.

ENDCLASS.
