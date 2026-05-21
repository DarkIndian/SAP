@AccessControl.authorizationCheck: #DEPENDENT_ON_REQUESTER
@EndUserText.label: 'SC Upload Result - Interface View'
define view entity ZI_SC_UPLOAD_RES_NHL
  as select from zsc_upload_res_nhl
  association to parent ZI_SC_UPLOAD_RUN_NHL as _Run
    on $projection.UploadRunUuid = _Run.UploadRunUuid
{
  key upload_run_uuid    as UploadRunUuid,
  key result_seq         as ResultSeq,
  source_sheet           as SourceSheet,
  source_row             as SourceRow,
  contract_ref_id        as ContractRefId,
  action                 as Action,
  service_contract       as ServiceContract,
  http_status            as HttpStatus,
  result_status          as ResultStatus,
  error_code             as ErrorCode,
  error_message          as ErrorMessage,
  error_target           as ErrorTarget,
  processed_at           as ProcessedAt,
  _Run
}
