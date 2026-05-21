INTERFACE zif_sc_api_client_nhl
  PUBLIC.

  TYPES:
    BEGIN OF ty_api_result,
      success          TYPE abap_bool,
      service_contract TYPE char12,
      http_status      TYPE i,
      error_message    TYPE string,
      error_target     TYPE string,
      error_code       TYPE char8,
    END OF ty_api_result.

  METHODS:
    create_contract
      IMPORTING
        is_header       TYPE zif_sc_api_client_nhl=>ty_header_payload
        it_items        TYPE zif_sc_api_client_nhl=>tt_item_payload
      RETURNING
        VALUE(rs_result) TYPE zif_sc_api_client_nhl=>ty_api_result,

    update_contract
      IMPORTING
        iv_contract     TYPE char12
        is_header       TYPE zif_sc_api_client_nhl=>ty_header_payload
        it_items        TYPE zif_sc_api_client_nhl=>tt_item_payload
      RETURNING
        VALUE(rs_result) TYPE zif_sc_api_client_nhl=>ty_api_result.

  TYPES:
    BEGIN OF ty_billing_plan_item,
      billing_plan_item_date   TYPE d,
      billing_plan_item_amount TYPE string,
      transaction_currency     TYPE char3,
    END OF ty_billing_plan_item,
    tt_billing_plan_item TYPE STANDARD TABLE OF ty_billing_plan_item WITH DEFAULT KEY,

    BEGIN OF ty_partner_item,
      partner_function  TYPE char2,
      business_partner  TYPE char10,
    END OF ty_partner_item,
    tt_partner_item TYPE STANDARD TABLE OF ty_partner_item WITH DEFAULT KEY,

    BEGIN OF ty_item_payload,
      service_contract_item            TYPE char6,
      product                          TYPE char40,
      service_doc_item_description     TYPE char40,
      service_contract_item_start_date TYPE d,
      service_contract_item_end_date   TYPE d,
      wbs_element                      TYPE char24,
      order_quantity                   TYPE string,
      order_quantity_unit              TYPE char3,
      net_amount                       TYPE string,
      transaction_currency             TYPE char3,
      yy1_recv_comp_code               TYPE char4,
      yy1_recv_profit_center           TYPE char10,
      billing_plan_items               TYPE tt_billing_plan_item,
      partners                         TYPE tt_partner_item,
    END OF ty_item_payload,
    tt_item_payload TYPE STANDARD TABLE OF ty_item_payload WITH DEFAULT KEY,

    BEGIN OF ty_header_payload,
      service_contract_type             TYPE char4,
      sold_to_party                     TYPE char10,
      service_doc_description           TYPE char40,
      service_contract_start_date       TYPE d,
      service_contract_end_date         TYPE d,
      contact_person                    TYPE char10,
      employee_responsible              TYPE char8,
      sales_organization                TYPE char4,
      distribution_channel              TYPE char2,
      division                          TYPE char2,
      requested_service_start_date      TYPE d,
      signature_date                    TYPE d,
      wbs_element                       TYPE char24,
      yy1_billing_summary_ind_sdh       TYPE char10,
      yy1_billing_description_sdh       TYPE char60,
      yy1_billingheaderterri            TYPE char30,
      yy1_billingheaderautom            TYPE d,
      yy1_billing_item_summary          TYPE char60,
      yy1_billingheadercateg            TYPE char30,
      yy1_billingheaderdateo            TYPE d,
      yy1_billingheaderearly            TYPE d,
      yy1_billingheaderinitia           TYPE char4,
      yy1_billingheadernegot            TYPE d,
      yy1_billingheaderoptio            TYPE d,
      yy1_overridebillingite            TYPE char1,
      yy1_billingheaderrenew            TYPE d,
      yy1_billingheadersubca            TYPE char30,
      sales_employees                   TYPE tt_partner_item,
    END OF ty_header_payload.

ENDINTERFACE.
