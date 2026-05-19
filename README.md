# Overdraft Batch Job – Application Job Framework

## Overview

This package delivers the Overdraft Batch Job as both an **Application Job Framework (AJF)** artefact and a classical **ABAP report**, so it can be scheduled from F1240, SM36/SM37, external schedulers, internal ABAP APIs, or as a recurring job.

---

## Artefacts

| Artefact | File | Purpose |
|---|---|---|
| AJF Class | `src/apj/ZCL_BATCH_OVERDRAFT_JOB.abap` | AJF execution class – primary approach |
| Classical Report | `src/report/ZREP_OVERDRAFT_JOB.abap` | SM36 / SUBMIT fallback |
| AJF Registration | `src/apj/ZCATALOG_OVERDRAFT_JOB.abap` | Catalog + template registration helper |
| Config Table DDL | `src/ddic/ZTOVERDRAFT_CONFIG.abap` | Table & domain specification |
| Table Types DDL | `src/ddic/ZTT_IBAN.abap` | ZTT_IBAN, ZTT_PRODUCT spec |

---

## DDIC Objects to Create (SE11)

### Domain: `ZDE_LIMIT_TYPE` (CHAR 10)
| Value | Description |
|---|---|
| `NOLIMIT` | No Limit |
| `EXTLIMIT` | External Limit |
| `INTLIMIT` | Internal Limit |

### Table: `ZTOVERDRAFT_CONFIG`
Transparent table holding default parameter values.  See `src/ddic/ZTOVERDRAFT_CONFIG.abap` for field list.

### Authorization Object: `Z_OD_JOB`
| Field | Values |
|---|---|
| `ACTVT` | `16` (Execute) |
| `Z_BPAREA` | Bank Posting Area (optional restriction) |

### Message Class: `ZOVERDRAFT`
| No. | Text |
|---|---|
| 001 | User &1 not authorised for bank posting area &2 |
| 002 | Cross-dependency validation failed. Check parameters. |

---

## Parameters

### Mandatory
| Parameter | Type | Description |
|---|---|---|
| P_ODSINCE | DATS | Overdraft Since Date |
| P_KEYDT | DATS | Key Date |
| P_BPAREA | CHAR10 | Bank Posting Area |
| P_SPOOL | CHAR1 | Spool output flag (radio button) |
| P_LIMTYPE | ZDE_LIMIT_TYPE | Limit Type (NOLIMIT / EXTLIMIT / INTLIMIT) |

### Optional
| Parameter | Type | Description |
|---|---|---|
| S_EXTACC | CHAR35 | External Account Number |
| S_REGION | REGIO | Region |
| S_BANKKEY | BANKK | Bank Key |
| S_IBAN | IBAN (range) | IBAN list |
| S_PRODUCT | CHAR40 (range) | Product(s) |
| P_CURR | WAERS | Currency |
| P_MINOVD | WERTV8 | Minimum Overdraft |

---

## Cross-Dependency Rules

| Rule | Condition | Outcome |
|---|---|---|
| I | Currency filled XOR Minimum Overdraft filled | Error – both must be provided together |
| II | Any one of (Ext Acc No, Region, Bank Key) filled but not all three | Error – all three must be provided together |

---

## Execution Flow

```
START
  │
  ├─ Fill blanks from ZTOVERDRAFT_CONFIG (user values take precedence)
  │
  ├─ Authorization Check (Z_OD_JOB / ACTVT=16)
  │     └─ FAIL → log error + STOP
  │
  ├─ Cross-Dependency Validation (Rules I & II)
  │     └─ FAIL → log error + STOP
  │
  ├─ SELECT from CDS View ZCDS_OVERDRAFT_ITEMS
  │     ├─ Returns data  → write to spool (if P_SPOOL = 'X')
  │     └─ No data       → log warning, no spool output
  │
  └─ Save Application Log (ZOVERDRAFT / BATCH)
END
```

---

## Scheduling Modes

### 1. F1240 – Application Job Scheduler (Fiori)
1. Create catalog entry `ZOVERDRAFT_BATCH` pointing to `ZCL_BATCH_OVERDRAFT_JOB`.
2. Create a job template `ZOVERDRAFT_DEFAULT`, fill parameter defaults.
3. Schedule immediately, at a specific time, or with a recurrence pattern.

### 2. Classical SM36 / SM37
Schedule report `ZREP_OVERDRAFT_JOB` with a variant as a background job.

### 3. External Scheduler (TWS / Control-M / etc.)
Use the SAP XBP RFC interface or the AJF OData API:
```
POST /sap/opu/odata/SAP/APJ_RT_SRV/JobTemplates
```

### 4. Internal ABAP API
```abap
DATA(lo_rt) = cl_apj_rt=>get_instance( ).
lo_rt->schedule_job(
  iv_job_template_name = 'ZOVERDRAFT_DEFAULT'
  it_parameters        = lt_params ).
```

### 5. Recurring Jobs
Set a recurrence rule (daily/weekly/cron) in the F1240 / Fiori Scheduler when scheduling the template.

---

## Application Log
Both artefacts write to Application Log object `ZOVERDRAFT`, sub-object `BATCH`.  
View logs via transaction `SLG1` filtering on object `ZOVERDRAFT`.

---

## CDS View Placeholder
The code references `ZCDS_OVERDRAFT_ITEMS`.  Replace this with the actual CDS consumption view name in your system.  The view must expose at minimum the fields listed in `ty_overdraft_result` / `ty_result`.
