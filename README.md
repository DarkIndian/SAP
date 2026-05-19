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
| No. | Severity | Text |
|---|---|---|
| 001 | E | You are not authorized to run this job for bank posting area &2 (User: &1) |
| 010 | E | Overdraft since date &1 must not be in the future |
| 011 | E | Key date &1 must not be before overdraft since date &2 |
| 012 | E | Limit type &1 is invalid – use NOLIMIT, EXTLIMIT, or INTLIMIT |
| 013 | E | Bank posting area &1 does not exist |
| 020 | E | Minimum overdraft amount is required when currency is specified |
| 021 | E | Currency is required when minimum overdraft amount is specified |
| 022 | E | External account number, region, and bank key must all be provided together |

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

## Classical Report – Selection Screen Event Model

| Event | Trigger | Action |
|---|---|---|
| `INITIALIZATION` | Program load / variant apply | Fill blank parameters from `ZTOVERDRAFT_CONFIG` |
| `AT SELECTION-SCREEN ON p_odsince` | Field exit | Overdraft-since date must not be in the future |
| `AT SELECTION-SCREEN ON p_keydt` | Field exit | Key date must not precede overdraft-since date |
| `AT SELECTION-SCREEN ON p_bparea` | Field exit | Bank posting area existence check |
| `AT SELECTION-SCREEN ON p_limtype` | Field exit | Limit type value must match domain `ZDE_LIMIT_TYPE` |
| `AT SELECTION-SCREEN` | F8 Execute | Authorization check + cross-field Rules I & II |
| `START-OF-SELECTION` | After all checks pass | CDS call → spool output → Application Log save |

`MESSAGE e...` in selection screen events redisplays the screen with the error at the bottom; the job cannot proceed until all checks pass. In background mode the same MESSAGE terminates the job and writes to the job log.

## Execution Flow (START-OF-SELECTION only)

```
START-OF-SELECTION  ← reached only after all screen events pass
  │
  ├─ Initialize Application Log (ZOVERDRAFT / BATCH)
  │
  ├─ SELECT from CDS View ZCDS_OVERDRAFT_ITEMS
  │     ├─ Returns data  → write to spool (if P_SPOOL = 'X')
  │     └─ No data       → log warning, no spool output
  │
  └─ Save Application Log → view via SLG1
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
