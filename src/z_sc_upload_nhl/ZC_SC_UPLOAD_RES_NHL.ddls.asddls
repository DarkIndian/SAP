@EndUserText.label: 'SC Upload Result - Consumption Projection'
@AccessControl.authorizationCheck: #INHERITED

define view entity ZC_SC_UPLOAD_RES_NHL
  provider contract transactional_ui
  as projection on ZI_SC_UPLOAD_RES_NHL
{
  key UploadRunUuid,
  key ResultSeq,
  SourceSheet,
  SourceRow,
  ContractRefId,
  Action,
  ServiceContract,
  HttpStatus,
  ResultStatus,

  case ResultStatus
    when 'SUCCESS' then 3
    when 'WARNING' then 2
    when 'ERROR'   then 1
    else                0
  end                   as ResultCriticality,

  ErrorCode,
  ErrorMessage,
  ErrorTarget,
  ProcessedAt,
  _Run : redirected to ZC_SC_UPLOAD_RUN_NHL
}
