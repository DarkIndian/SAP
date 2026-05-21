CLASS zcl_sc_api_client_nhl DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    INTERFACES zif_sc_api_client_nhl.

    CONSTANTS:
      gc_comm_scenario TYPE string VALUE 'SAP_COM_0558',
      gc_api_path      TYPE string VALUE '/sap/opu/odata/sap/API_SERVICE_CONTRACT_SRV/A_ServiceContract',
      gc_content_type  TYPE string VALUE 'application/json',
      gc_accept        TYPE string VALUE 'application/json'.

  PRIVATE SECTION.

    METHODS:
      build_json_payload
        IMPORTING
          is_header        TYPE zif_sc_api_client_nhl=>ty_header_payload
          it_items         TYPE zif_sc_api_client_nhl=>tt_item_payload
        RETURNING
          VALUE(rv_json)   TYPE string,

      build_item_json
        IMPORTING
          is_item          TYPE zif_sc_api_client_nhl=>ty_item_payload
        RETURNING
          VALUE(rv_json)   TYPE string,

      build_billing_json
        IMPORTING
          it_billing       TYPE zif_sc_api_client_nhl=>tt_billing_plan_item
        RETURNING
          VALUE(rv_json)   TYPE string,

      build_partner_json
        IMPORTING
          it_partners      TYPE zif_sc_api_client_nhl=>tt_partner_item
        RETURNING
          VALUE(rv_json)   TYPE string,

      date_to_iso
        IMPORTING
          iv_date          TYPE d
        RETURNING
          VALUE(rv_iso)    TYPE string,

      escape_json
        IMPORTING
          iv_value         TYPE string
        RETURNING
          VALUE(rv_escaped) TYPE string,

      call_with_retry
        IMPORTING
          iv_method        TYPE string
          iv_path          TYPE string
          iv_body          TYPE string
          iv_contract      TYPE char12 OPTIONAL
        RETURNING
          VALUE(rs_result) TYPE zif_sc_api_client_nhl=>ty_api_result,

      do_http_call
        IMPORTING
          iv_method        TYPE string
          iv_path          TYPE string
          iv_body          TYPE string
        EXPORTING
          ev_http_status   TYPE i
          ev_body          TYPE string.

ENDCLASS.


CLASS zcl_sc_api_client_nhl IMPLEMENTATION.

  METHOD zif_sc_api_client_nhl~create_contract.
    DATA(lv_json) = build_json_payload(
      is_header = is_header
      it_items  = it_items ).

    rs_result = call_with_retry(
      iv_method = 'POST'
      iv_path   = gc_api_path
      iv_body   = lv_json ).
  ENDMETHOD.


  METHOD zif_sc_api_client_nhl~update_contract.
    DATA(lv_path) = |{ gc_api_path }('{ iv_contract }')|.
    DATA(lv_json) = build_json_payload(
      is_header = is_header
      it_items  = it_items ).

    rs_result = call_with_retry(
      iv_method   = 'PATCH'
      iv_path     = lv_path
      iv_body     = lv_json
      iv_contract = iv_contract ).
  ENDMETHOD.


  METHOD call_with_retry.
    do_http_call(
      EXPORTING iv_method      = iv_method
                iv_path        = iv_path
                iv_body        = iv_body
      IMPORTING ev_http_status = DATA(lv_status)
                ev_body        = DATA(lv_body) ).

    IF lv_status >= 500.
      " One retry on transient server error
      do_http_call(
        EXPORTING iv_method      = iv_method
                  iv_path        = iv_path
                  iv_body        = iv_body
        IMPORTING ev_http_status = lv_status
                  ev_body        = lv_body ).
    ENDIF.

    rs_result-http_status = lv_status.

    IF lv_status = 201 OR lv_status = 200.
      rs_result-success = abap_true.
      " Extract contract number from response JSON
      DATA(lv_search) = '"ServiceContract":"'.
      DATA(lv_pos) = find( val = lv_body sub = lv_search ).
      IF lv_pos >= 0.
        DATA(lv_start) = lv_pos + strlen( lv_search ).
        DATA(lv_end)   = find( val = lv_body sub = '"' off = lv_start ).
        IF lv_end > lv_start.
          rs_result-service_contract = substring( val = lv_body off = lv_start len = lv_end - lv_start ).
        ENDIF.
      ENDIF.
    ELSE.
      rs_result-success = abap_false.
      " Extract OData error message
      DATA(lv_msg_search) = '"message":"'.
      DATA(lv_mp) = find( val = lv_body sub = lv_msg_search ).
      IF lv_mp >= 0.
        DATA(lv_ms) = lv_mp + strlen( lv_msg_search ).
        DATA(lv_me) = find( val = lv_body sub = '"' off = lv_ms ).
        IF lv_me > lv_ms.
          rs_result-error_message = substring( val = lv_body off = lv_ms len = lv_me - lv_ms ).
        ENDIF.
      ENDIF.
      IF rs_result-error_message IS INITIAL.
        rs_result-error_message = lv_body.
      ENDIF.
      " Extract target field
      DATA(lv_tgt_search) = '"target":"'.
      DATA(lv_tp) = find( val = lv_body sub = lv_tgt_search ).
      IF lv_tp >= 0.
        DATA(lv_ts) = lv_tp + strlen( lv_tgt_search ).
        DATA(lv_te) = find( val = lv_body sub = '"' off = lv_ts ).
        IF lv_te > lv_ts.
          rs_result-error_target = substring( val = lv_body off = lv_ts len = lv_te - lv_ts ).
        ENDIF.
      ENDIF.
      rs_result-error_code = SWITCH #( lv_status
        WHEN 401 OR 403 THEN 'SCUP_101'
        WHEN 404        THEN 'SCUP_110'
        WHEN 412        THEN 'SCUP_111'
        WHEN 408        THEN 'SCUP_103'
        ELSE COND #( WHEN lv_status >= 500 THEN 'SCUP_102' ELSE 'SCUP_100' ) ).
    ENDIF.
  ENDMETHOD.


  METHOD do_http_call.
    TRY.
        DATA(lo_dest) = cl_http_destination_provider=>create_by_comm_arrangement(
          comm_scenario  = gc_comm_scenario
          service_id     = 'API_SERVICE_CONTRACT_SRV_0001' ).

        DATA(lo_http) = cl_web_http_client_manager=>create_by_http_destination( lo_dest ).
        DATA(lo_req)  = lo_http->get_http_request( ).

        lo_req->set_header_field( i_name = 'Content-Type' i_value = gc_content_type ).
        lo_req->set_header_field( i_name = 'Accept'       i_value = gc_accept ).
        lo_req->set_uri_path( iv_path ).
        IF iv_body IS NOT INITIAL.
          lo_req->set_text( iv_body ).
        ENDIF.

        DATA(lo_resp) = SWITCH #( iv_method
          WHEN 'POST'  THEN lo_http->execute( if_web_http_client=>post )
          WHEN 'PATCH' THEN lo_http->execute( if_web_http_client=>patch )
          ELSE              lo_http->execute( if_web_http_client=>get ) ).

        ev_http_status = lo_resp->get_status( )-code.
        ev_body        = lo_resp->get_text( ).

      CATCH cx_http_dest_provider_error
            cx_web_http_client_error
            cx_web_message_error INTO DATA(lx).
        ev_http_status = 500.
        ev_body        = lx->get_text( ).
    ENDTRY.
  ENDMETHOD.


  METHOD build_json_payload.
    DATA(lv_start_date) = date_to_iso( is_header-service_contract_start_date ).
    DATA(lv_end_date)   = date_to_iso( is_header-service_contract_end_date ).

    DATA lv_items TYPE string.
    LOOP AT it_items INTO DATA(ls_item).
      IF lv_items IS NOT INITIAL. lv_items = lv_items && ','. ENDIF.
      lv_items = lv_items && build_item_json( ls_item ).
    ENDLOOP.

    rv_json = |{| &&
      |"ServiceContractType":"{ escape_json( CONV #( is_header-service_contract_type ) )}",| &&
      |"SoldToParty":"{ escape_json( CONV #( is_header-sold_to_party ) )}",| &&
      |"ServiceDocDescription":"{ escape_json( CONV #( is_header-service_doc_description ) )}",| &&
      |"ServiceContractStartDate":"{ lv_start_date }",| &&
      |"ServiceContractEndDate":"{ lv_end_date }",| &&
      COND #( WHEN is_header-contact_person IS NOT INITIAL
              THEN |"ContactPerson":"{ escape_json( CONV #( is_header-contact_person ) )}",| ) &&
      COND #( WHEN is_header-employee_responsible IS NOT INITIAL
              THEN |"EmployeeResponsible":"{ escape_json( CONV #( is_header-employee_responsible ) )}",| ) &&
      |"SalesOrganization":"{ escape_json( CONV #( is_header-sales_organization ) )}",| &&
      |"DistributionChannel":"{ escape_json( CONV #( is_header-distribution_channel ) )}",| &&
      |"Division":"{ escape_json( CONV #( is_header-division ) )}",| &&
      COND #( WHEN is_header-wbs_element IS NOT INITIAL
              THEN |"WBSElement":"{ escape_json( CONV #( is_header-wbs_element ) )}",| ) &&
      COND #( WHEN is_header-yy1_billing_summary_ind_sdh IS NOT INITIAL
              THEN |"YY1_BillingSummaryInd_SDH":"{ escape_json( CONV #( is_header-yy1_billing_summary_ind_sdh ) )}",| ) &&
      COND #( WHEN is_header-yy1_billing_description_sdh IS NOT INITIAL
              THEN |"YY1_BillingDescription_SDH":"{ escape_json( CONV #( is_header-yy1_billing_description_sdh ) )}",| ) &&
      COND #( WHEN is_header-yy1_billingheaderterri IS NOT INITIAL
              THEN |"YY1_billingheaderterri":"{ escape_json( CONV #( is_header-yy1_billingheaderterri ) )}",| ) &&
      COND #( WHEN is_header-yy1_billing_item_summary IS NOT INITIAL
              THEN |"YY1_BillingItemSummary":"{ escape_json( CONV #( is_header-yy1_billing_item_summary ) )}",| ) &&
      COND #( WHEN is_header-yy1_billingheadercateg IS NOT INITIAL
              THEN |"YY1_billingheadercateg":"{ escape_json( CONV #( is_header-yy1_billingheadercateg ) )}",| ) &&
      COND #( WHEN is_header-yy1_billingheaderinitia IS NOT INITIAL
              THEN |"YY1_BillingheaderInitia":"{ escape_json( CONV #( is_header-yy1_billingheaderinitia ) )}",| ) &&
      COND #( WHEN is_header-yy1_overridebillingite IS NOT INITIAL
              THEN |"YY1_Overridebillingite":"{ escape_json( CONV #( is_header-yy1_overridebillingite ) )}",| ) &&
      COND #( WHEN is_header-yy1_billingheadersubca IS NOT INITIAL
              THEN |"YY1_billingheaderSubCa":"{ escape_json( CONV #( is_header-yy1_billingheadersubca ) )}",| ) &&
      |"to_ServiceContractItem":{"results":[{ lv_items }]}| &&
      |}|.
  ENDMETHOD.


  METHOD build_item_json.
    DATA(lv_billing) = build_billing_json( is_item-billing_plan_items ).
    DATA(lv_partners) = build_partner_json( is_item-partners ).

    rv_json = |{| &&
      |"ServiceContractItem":"{ escape_json( CONV #( is_item-service_contract_item ) )}",| &&
      |"Product":"{ escape_json( CONV #( is_item-product ) )}",| &&
      COND #( WHEN is_item-service_doc_item_description IS NOT INITIAL
              THEN |"ServiceDocItemDescription":"{ escape_json( CONV #( is_item-service_doc_item_description ) )}",| ) &&
      COND #( WHEN is_item-service_contract_item_start_date IS NOT INITIAL AND is_item-service_contract_item_start_date <> '00000000'
              THEN |"ServiceContractItemStartDate":"{ date_to_iso( is_item-service_contract_item_start_date ) }",| ) &&
      COND #( WHEN is_item-service_contract_item_end_date IS NOT INITIAL AND is_item-service_contract_item_end_date <> '00000000'
              THEN |"ServiceContractItemEndDate":"{ date_to_iso( is_item-service_contract_item_end_date ) }",| ) &&
      COND #( WHEN is_item-wbs_element IS NOT INITIAL
              THEN |"WBSElement":"{ escape_json( CONV #( is_item-wbs_element ) )}",| ) &&
      COND #( WHEN is_item-order_quantity IS NOT INITIAL
              THEN |"OrderQuantity":"{ is_item-order_quantity }",| ) &&
      COND #( WHEN is_item-order_quantity_unit IS NOT INITIAL
              THEN |"OrderQuantityUnit":"{ escape_json( CONV #( is_item-order_quantity_unit ) )}",| ) &&
      COND #( WHEN is_item-net_amount IS NOT INITIAL
              THEN |"NetAmount":"{ is_item-net_amount }",| ) &&
      COND #( WHEN is_item-transaction_currency IS NOT INITIAL
              THEN |"TransactionCurrency":"{ escape_json( CONV #( is_item-transaction_currency ) )}",| ) &&
      COND #( WHEN is_item-yy1_recv_comp_code IS NOT INITIAL
              THEN |"YY1_RecvCompCode":"{ escape_json( CONV #( is_item-yy1_recv_comp_code ) )}",| ) &&
      COND #( WHEN is_item-yy1_recv_profit_center IS NOT INITIAL
              THEN |"YY1_RecvProfitCenter":"{ escape_json( CONV #( is_item-yy1_recv_profit_center ) )}",| ) &&
      |"to_SrvcContrItmBillingPlanItem":{"results":[{ lv_billing }]},| &&
      |"to_ServiceContractPartner":{"results":[{ lv_partners }]}| &&
      |}|.
  ENDMETHOD.


  METHOD build_billing_json.
    LOOP AT it_billing INTO DATA(ls_b).
      IF rv_json IS NOT INITIAL. rv_json = rv_json && ','. ENDIF.
      rv_json = rv_json &&
        |{"BillingPlanItemDate":"{ date_to_iso( ls_b-billing_plan_item_date ) }",| &&
        |"BillingPlanItemAmount":"{ ls_b-billing_plan_item_amount }",| &&
        |"TransactionCurrency":"{ escape_json( CONV #( ls_b-transaction_currency ) )}"}|.
    ENDLOOP.
  ENDMETHOD.


  METHOD build_partner_json.
    LOOP AT it_partners INTO DATA(ls_p).
      IF rv_json IS NOT INITIAL. rv_json = rv_json && ','. ENDIF.
      rv_json = rv_json &&
        |{"PartnerFunction":"{ escape_json( CONV #( ls_p-partner_function ) )}",| &&
        |"BusinessPartner":"{ escape_json( CONV #( ls_p-business_partner ) )}"}|.
    ENDLOOP.
  ENDMETHOD.


  METHOD date_to_iso.
    " Convert ABAP date (YYYYMMDD) to ISO 8601 (YYYY-MM-DD)
    CHECK iv_date IS NOT INITIAL AND iv_date <> '00000000'.
    rv_iso = |{ iv_date(4) }-{ iv_date+4(2) }-{ iv_date+6(2) }|.
  ENDMETHOD.


  METHOD escape_json.
    rv_escaped = replace( val = iv_value sub = '\' with = '\\' occ = 0 ).
    rv_escaped = replace( val = rv_escaped sub = '"' with = '\"' occ = 0 ).
  ENDMETHOD.

ENDCLASS.
