@EndUserText.label: 'SC Upload Run - Consumption Projection'
@AccessControl.authorizationCheck: #INHERITED

@UI.headerInfo:
  { typeName: 'Upload Run',
    typeNamePlural: 'Upload Runs',
    title.value: 'FileName',
    description.value: 'OverallStatus' }

define root view entity ZC_SC_UPLOAD_RUN_NHL
  provider contract transactional_ui
  as projection on ZI_SC_UPLOAD_RUN_NHL
{
  key UploadRunUuid,
  UploadTimestamp,
  UploadedBy,
  FileName,
  FileSizeBytes,
  FileHash,
  TotalRecords,
  SuccessCount,
  FailedCount,
  OverallStatus,

  case OverallStatus
    when 'COMPLETED' then 3
    when 'RUNNING'   then 2
    when 'FAILED'    then 1
    else                  0
  end                    as StatusCriticality,

  BaliLogHandle,
  CreatedBy,
  CreatedAt,
  LastChangedBy,
  LastChangedAt,
  _Result : redirected to composition child ZC_SC_UPLOAD_RES_NHL
}
