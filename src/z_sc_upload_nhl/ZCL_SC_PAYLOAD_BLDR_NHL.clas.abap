CLASS zcl_sc_payload_bldr_nhl DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    CLASS-METHODS:
      build
        IMPORTING
          is_header        TYPE zcl_sc_xlsx_reader_nhl=>ty_header_row
          it_items         TYPE zcl_sc_xlsx_reader_nhl=>tt_item_rows
          it_billing       TYPE zcl_sc_xlsx_reader_nhl=>tt_billing_rows
          it_partners      TYPE zcl_sc_xlsx_reader_nhl=>tt_partner_rows
          it_sales_empls   TYPE zcl_sc_xlsx_reader_nhl=>tt_salesempl_rows
        EXPORTING
          es_header_payload TYPE zif_sc_api_client_nhl=>ty_header_payload
          et_item_payloads  TYPE zif_sc_api_client_nhl=>tt_item_payload.

  PRIVATE SECTION.

    CLASS-METHODS:
      parse_date_ddmmyyyy
        IMPORTING
          iv_raw_date      TYPE string
        RETURNING
          VALUE(rv_date)   TYPE d,

      normalise_numeric
        IMPORTING
          iv_raw           TYPE string
        RETURNING
          VALUE(rv_norm)   TYPE string,

      pad_partner_number
        IMPORTING
          iv_raw           TYPE string
        RETURNING
          VALUE(rv_padded) TYPE string.

ENDCLASS.


CLASS zcl_sc_payload_bldr_nhl IMPLEMENTATION.

  METHOD build.
    " Build header payload
    es_header_payload = VALUE #(
      service_contract_type             = CONV #( is_header-service_contract_type )
      sold_to_party                     = CONV #( pad_partner_number( is_header-sold_to_party ) )
      service_doc_description           = CONV #( is_header-service_doc_desc )
      service_contract_start_date       = parse_date_ddmmyyyy( is_header-start_date_raw )
      service_contract_end_date         = parse_date_ddmmyyyy( is_header-end_date_raw )
      contact_person                    = CONV #( pad_partner_number( is_header-contact_person ) )
      employee_responsible              = CONV #( is_header-employee_responsible )
      sales_organization                = CONV #( is_header-sales_org )
      distribution_channel              = CONV #( is_header-dist_channel )
      division                          = CONV #( is_header-division )
      requested_service_start_date      = parse_date_ddmmyyyy( is_header-req_start_date_raw )
      signature_date                    = parse_date_ddmmyyyy( is_header-signature_date_raw )
      wbs_element                       = CONV #( is_header-wbs_element )
      yy1_billing_summary_ind_sdh       = CONV #( is_header-yy1_billing_summary_ind )
      yy1_billing_description_sdh       = CONV #( is_header-yy1_billing_description )
      yy1_billingheaderterri            = CONV #( is_header-yy1_billing_header_terri )
      yy1_billingheaderautom            = parse_date_ddmmyyyy( is_header-yy1_billing_header_autom )
      yy1_billing_item_summary          = CONV #( is_header-yy1_billing_item_summary )
      yy1_billingheadercateg            = CONV #( is_header-yy1_billing_header_categ )
      yy1_billingheaderdateo            = parse_date_ddmmyyyy( is_header-yy1_billing_header_dateo )
      yy1_billingheaderearly            = parse_date_ddmmyyyy( is_header-yy1_billing_header_early )
      yy1_billingheaderinitia           = CONV #( is_header-yy1_billing_header_initia )
      yy1_billingheadernegot            = parse_date_ddmmyyyy( is_header-yy1_billing_header_negot )
      yy1_billingheaderoptio            = parse_date_ddmmyyyy( is_header-yy1_billing_header_optio )
      yy1_overridebillingite            = CONV #( is_header-yy1_override_billing_ite )
      yy1_billingheaderrenew            = parse_date_ddmmyyyy( is_header-yy1_billing_header_renew )
      yy1_billingheadersubca            = CONV #( is_header-yy1_billing_header_subca )
    ).

    " Add sales employees as partner entries on the header
    LOOP AT it_sales_empls INTO DATA(ls_emp)
         WHERE ref_id = is_header-ref_id.
      APPEND VALUE #(
        partner_function = CONV #( ls_emp-partner_function )
        business_partner = CONV #( pad_partner_number( ls_emp-employee_number ) )
      ) TO es_header_payload-sales_employees.
    ENDLOOP.

    " Build item payloads
    LOOP AT it_items INTO DATA(ls_item)
         WHERE ref_id = is_header-ref_id.

      DATA ls_item_payload TYPE zif_sc_api_client_nhl=>ty_item_payload.
      ls_item_payload = VALUE #(
        service_contract_item            = CONV #( ls_item-item_no )
        product                          = CONV #( ls_item-product )
        service_doc_item_description     = CONV #( ls_item-item_desc )
        service_contract_item_start_date = parse_date_ddmmyyyy( ls_item-start_date_raw )
        service_contract_item_end_date   = parse_date_ddmmyyyy( ls_item-end_date_raw )
        wbs_element                      = CONV #( ls_item-wbs_element )
        order_quantity                   = normalise_numeric( ls_item-order_qty_raw )
        order_quantity_unit              = CONV #( ls_item-order_qty_unit )
        net_amount                       = normalise_numeric( ls_item-net_amount_raw )
        transaction_currency             = CONV #( to_upper( ls_item-currency ) )
        yy1_recv_comp_code               = CONV #( ls_item-yy1_recv_comp_code )
        yy1_recv_profit_center           = CONV #( ls_item-yy1_recv_profit_center )
      ).

      " Add billing plan items for this item
      LOOP AT it_billing INTO DATA(ls_bill)
           WHERE ref_id = ls_item-ref_id AND item_no = ls_item-item_no.
        APPEND VALUE #(
          billing_plan_item_date   = parse_date_ddmmyyyy( ls_bill-billing_date_raw )
          billing_plan_item_amount = normalise_numeric( ls_bill-amount_raw )
          transaction_currency     = CONV #( to_upper( ls_bill-currency ) )
        ) TO ls_item_payload-billing_plan_items.
      ENDLOOP.

      " Add item-level partners
      LOOP AT it_partners INTO DATA(ls_part)
           WHERE ref_id = ls_item-ref_id AND item_no = ls_item-item_no.
        APPEND VALUE #(
          partner_function = CONV #( ls_part-partner_function )
          business_partner = CONV #( pad_partner_number( ls_part-business_partner ) )
        ) TO ls_item_payload-partners.
      ENDLOOP.

      APPEND ls_item_payload TO et_item_payloads.
    ENDLOOP.
  ENDMETHOD.


  METHOD parse_date_ddmmyyyy.
    " DD/MM/YYYY → YYYYMMDD
    CHECK iv_raw_date IS NOT INITIAL AND strlen( iv_raw_date ) = 10.
    CHECK iv_raw_date+2(1) = '/' AND iv_raw_date+5(1) = '/'.
    rv_date = |{ iv_raw_date+6(4) }{ iv_raw_date+3(2) }{ iv_raw_date(2) }|.
  ENDMETHOD.


  METHOD normalise_numeric.
    " Replace comma decimal separator with period; strip thousand separators
    rv_norm = replace( val = iv_raw sub = ',' with = '.' occ = 0 ).
    rv_norm = condense( rv_norm ).
  ENDMETHOD.


  METHOD pad_partner_number.
    " Left-pad numeric partner numbers with zeros to 10 characters
    rv_padded = iv_raw.
    CHECK iv_raw IS NOT INITIAL.
    TRY.
        DATA lv_int TYPE i.
        lv_int = iv_raw.
        rv_padded = |{ lv_int WIDTH = 10 ALIGN = RIGHT PAD = '0' }|.
      CATCH cx_sy_conversion_error.
        rv_padded = iv_raw.  " Non-numeric: return as-is
    ENDTRY.
  ENDMETHOD.

ENDCLASS.
