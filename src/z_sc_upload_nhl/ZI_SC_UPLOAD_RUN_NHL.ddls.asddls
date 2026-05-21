@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'SC Upload Run - Interface View'
define root view entity ZI_SC_UPLOAD_RUN_NHL
  as select from zsc_upload_run_nhl
  composition [0..*] of ZI_SC_UPLOAD_RES_NHL as _Result
{
  key upload_run_uuid    as UploadRunUuid,
  upload_timestamp       as UploadTimestamp,
  uploaded_by            as UploadedBy,
  file_name              as FileName,
  file_size_bytes        as FileSizeBytes,
  file_hash              as FileHash,
  total_records          as TotalRecords,
  success_count          as SuccessCount,
  failed_count           as FailedCount,
  overall_status         as OverallStatus,
  bali_log_handle        as BaliLogHandle,
  created_by             as CreatedBy,
  created_at             as CreatedAt,
  last_changed_by        as LastChangedBy,
  last_changed_at        as LastChangedAt,
  _Result
}
