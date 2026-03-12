• A comprehensive view of major database tables.

    ---
    Database Tables Used in Keycloak Integration

    Overview Diagram


    +----------------------------------------------------------------------------------------+
    |                              DATABASE TABLE ARCHITECTURE                                |
    |                                                                                         |
    |  +- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -+  |
    |  |                    Primavera P6 Source Tables (DC01_*)                            |  |
    |  |                                                                                   |  |
    |  |  +----------------+    +------------------+    +------------------+              |  |
    |  |  |  DC01_userr    |    |  DC01_resource   |    |  DC01_userOBS    |              |  |
    |  |  |  (Users)       |    |  (Employees)     |    |  (User-OBS Assign)|             |  |
    |  |  +----------------+    +------------------+    +------------------+              |  |
    |  |          |                      |                        |                       |  |
    |  |          +----------------------+------------------------+                       |  |
    |  |                                 |                                                |  |
    |  |  +----------------+    +------------------+    +------------------+              |  |
    |  |  |  DC01_OBS      |    |  DC01_EPS        |    |  DC01_project    |              |  |
    |  |  |  (Org Structure)|   |  (Project        |    |  (Projects)      |              |  |
    |  |  |                |    |  Hierarchy)      |    |                  |              |  |
    |  |  +----------------+    +------------------+    +------------------+              |  |
    |  |                                                                                  |  |
    |  |  +----------------+    +------------------+    +-------------------+             |  |
    |  |  |DC01_resourceCode|   |DC01_resourceCode |    |DC01_projectProfile|             |  |
    |  |  |(Cost Centers)  |    |Assignment (CC Map)|   |(Permissions)      |             |  |
    |  |  +----------------+    +------------------+    +-------------------+             |  |
    |  +- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -+  |
    |                                      |                                                  |
    |                                      ▼                                                  |
    |  +- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -+  |
    |  |                          Application Tables (Custom)                              |  |
    |  |                                                                                   |  |
    |  |      +---------------------------------------------------------------+           |  |
    |  |      |                       DC01_user_base                          |           |  |
    |  |      |                 (Main Authorization Table)                    |           |  |
    |  |      |  +-------------+------------+----------------+-------+----------+         |  |
    |  |      |  |KullaniciAdi | KaynakAdi  |MasrafYeriKodu  | Sifre |  Yetki   |         |  |
    |  |      |  +-------------+------------+----------------+-------+----------+         |  |
    |  |      |  | username1   | John...    | 1234567-8      | ***** | SUPERADMIN|        |  |
    |  |      |  | username2   | Mary...    | 7654321-6      | ***** | SUPERADMIN|        |  |
    |  |      |  +-------------+------------+----------------+-------+----------+         |  |
    |  |      +---------------------------------------------------------------+           |  |
    |  +- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -+  |
    |                                      |                                                  |
    |                                      ▼                                                  |
    +- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -+
                               R Data Files (.Rdata)
    ||                                                                                      ||
    ||  +----------------+    +------------------+    +-----------------+                  ||
    ||  | user_base      |    | proje_KYP_base   |    | proje_PY_base   |                  ||
    ||  | (User Auth)    |    | (Quality Auth)   |    | (Project Mgr)   |                  ||
    ||  +----------------+    +------------------+    +-----------------+                  ||
    ||                                                                                      ||
    ||  +----------------+    +------------------+    +-------------------+                ||
    ||  | proje_DirP_base|    | yetkiProje       |    | personelBilgileri |                ||
    ||  | (Director Auth)|    | (Project-EPS)    |    | (Employee Info)   |                ||
    ||  +----------------+    +------------------+    +-------------------+                ||
    ||                                                                                      ||
    +- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -+

---
1. Core Authorization Table

DC01_user_base (Primary Authorization Table)

| Column         | Type          | Description                                               |
| KullaniciAdi   | NVARCHAR(20)  | Username (matches Keycloakpre referred_username)          |

| KaynakAdi      | NVARCHAR(50)  | Full name of the employee                                 |

| MasrafYeriKodu | NVARCHAR(200) | Cost center code/s comma-sep for multi-department access  |

| Sifre          | NVARCHAR(20)  | Password (legacy, not used with Keycloak)                 |

| Yetki          | VARCHAR(5)    | Permiss: SUPERADMIN, ADMIN, DIR, DIR-P, KY-P, KY, PY, etc|

| UserObjectId   | INT           | Foreign key to Primavera P6 user                          |

Purpose: This is the main table that determines if a Keycloak-authenticated user can access the application. When a user authenticates via Keycloak, their preferred_username is looked up in this table.

Sample Data:

| KullaniciAdi | KaynakAdi | MasrafYeriKodu     | Sifre | Yetki      |
| username1    | John      | 1234567-8          | ***** | SUPERADMIN |
| username2    | Mary      | 1234567-8          | ***** | SUPERADMIN |
| admin        | admin     | 1234567-4          | admin | ADMIN      |
| kalite       | kalite    | 1234567-5          | kalite| KAL        |
| test         | test      | 1234567-6          | test  | TEST       |
| username9    | Scott     | 1234567-4,1234567-5| ***** | DIR        |

Creation Process (dailyQueryScript.R, lines 404-915):
-- Create temp table
CREATE TABLE [DatabaseName].[dbo].[DC01_user_base_temp] (
    KullaniciAdi NVARCHAR(20) NULL,
    KaynakAdi NVARCHAR(50) NULL,
    MasrafYeriKodu NVARCHAR(200) NULL,
    Sifre NVARCHAR(20) NULL,
    Yetki VARCHAR(5) NULL,
    UserObjectId INT NULL
)

-- Populate with complex query joining P6 tables...

-- Backup old table
DROP TABLE [DatabaseName].[dbo].[DC02_user_base]
EXEC sp_rename 'DC01_user_base', 'DC02_user_base'

-- Activate new table
EXEC sp_rename 'DC01_user_base_temp', 'DC01_user_base'

---
2. Primavera P6 Source Tables

DC01_userr (P6 Users)

| Column                    | Description          |

| ObjectId                  | Primary key          |

| Name                      | Username (login name)|

| UserInterfaceViewObjectId | UI configuration     |


Purpose: Contains all P6 system users. The Name field becomes KullaniciAdi in user_base.

-- Query example (line 696-711)
SELECT Name AS KullaniciAdi, ObjectId AS UserObjectId
FROM [DatabaseName].[dbo].[DC01_userr]

---
DC01_resource (Employees/Resources)


| Column             | Description           |

| ObjectId           | Primary key           |

| EmployeeId         | Employee ID (Sicil No)|

| Name               | Full name             |

| EmailAddress       | Email                 |

| OfficePhone        | Phone                 |

| Title              | Job title (Unvan)     |

| IsActive           | Active status (1/0)   |

| UserObjectId       | Link to DC01_userr    |

| ParentObjectId     | Parent resource       |

| PrimaryRoleName    | Primary role          |

| PrimaryRoleObjectId| Link to role          |


Purpose: Contains employee information from Primavera P6. Used to get employee details and link users to cost centers.

-- Query example (line 137-145)
SELECT res.ObjectId, res.EmployeeId, res.Name, res.Title, res.IsActive
FROM [DatabaseName].[dbo].[DC01_resource] res
WHERE EmployeeId IS NOT NULL


DC01_userOBS (User-OBS Assignment)


| Column                 | Description                                           |

| UserObjectId           | Link to DC01_userr                                    |

| OBSObjectId            | Link to DC01_OBS (Organizational Breakdown Structure) |

| ProjectProfileObjectId | Permission profile ID                                 |

| ProfileName            | Profile name (e.g., "PY", "PPTS")                     |

| UserName               | Username                                              |

| OBSName                | OBS name (e.g., "4_ABCDE-PY")                        |


Purpose: Maps users to organizational units and determines their permission levels. This is crucial for determining if a user is
- A Project Manager (PY profile)
- A Planning Specialist (PPTS profile)
- A Quality staff member (KY-P profile)
- An Administrator (Rapor Erişim - PY profile)

Key Profile IDs:


| Profile ID | Profile Name        | Meaning                                |

| 51         | PY                  | Project Manager                        |

| 81         | PPTS                | Project Planning & Tracking Specialist |

| 87         | PMO                 | Project Management Office              |

| 126        | Rapor Erişim - PY   | Report Access - Project Management     |

| 127        | Rapor Erişim - PPTS | Report Access - Planning               |


-- Query example (lines 944-959)
SELECT OBSObjectId, ProjectProfileObjectId, UserObjectId
FROM [DatabaseName].[dbo].[DC01_userOBS]
WHERE ProjectProfileObjectId = 126 -- Rapor Erişim - PY
    AND OBSObjectId IN (
        6623,
        6791,
        14966,
        ...
    )

---
DC01_OBS (Organizational Breakdown Structure)

| Column   | Description |

| ObjectId | Primary key |

| OBSName  | OBS name    |


Purpose: Defines the organizational hierarchy in P6. Used to determine which department/directorate a user belongs to.

---
DC01_EPS (Enterprise Project Structure)

| Column            | Description   |

| ObjectId          | Primary key   |

| Id                | EPS Code      |

| Name              | EPS Name      |

| OBSObjectId       | Link to OBS   |

| ParentEPSObjectId | Parent EPS nod|


Purpose: Defines the project hierarchy. Used to determine which projects a user can access based on their EPS assignments.

---
DC01_project (Projects)


| Column            | Description                        |

| ObjectId          | Primary key                        |

| Id                | Project ID                         |

| Name              | Project name                       |

| Status            | Status (Active, Planned, Completed)|

| OBSObjectId       | Link to OBS                        |

| ParentEPSObjectId | Link to EPS                        |


Purpose: Contains all projects. Used to filter projects by authorization level.

---
DC01_resourceCode (Cost Center Definitions)

| Column            | Description                             |

| ObjectId          | Primary key                             |

| CodeValue         | Cost center code (e.g., "1234567-8")   |

| Description       | Cost center name                        |

| CodeTypeObjectId  | Code type (41 = Masraf Yeri/Cost Center)|


Purpose: Defines cost centers for authorization. The CodeValue is stored in MasrafYeriKodu.

---
DC01_resourceCodeAssignment (Resource-Cost Center Mapping)

| Column                   | Description                                            |

| ResourceObjectId         | Link to DC01_resource                                  |

| ResourceCodeObjectId     | Link to DC01_resourceCode                              |

| ResourceCodeTypeObjectId | Code type (41=Masraf Yeri, 42=Puantaj, 43=SAP Aktivite)|

| ResourceCodeValue        | Cost center code                                       |


Purpose: Maps employees to cost centers. Used to determine MasrafYeriKodu for each user.

-- Query example (lines 141-143)
SELECT ResourceObjectId, ResourceCodeTypeObjectId, ResourceCodeValue
FROM [DatabaseName].[dbo].[DC01_resourceCodeAssignment]
WHERE ResourceCodeTypeObjectId IN (41, 42, 43)

---
DC01_projectProfile (Permission Profiles)


| Column      | Description  |

| ObjectId    | Primary key  |

| ProfileName | Profile name |


Purpose: Defines permission levels in P6. Used to determine user authorization.

---
DC01_resourceAccess (Resource Access Permissions)


| Column           | Description                                |

| UserObjectId     | Link to user                               |

| ResourceObjectId | Link to resource (for director permissions)|


Purpose: Maps users to resource nodes for access control. Used to determine director-level permissions.

---
DC01_userLicence (User Licenses)


| Column       | Description |

| ObjectId     | Primary key |

| UserObjectId | Link to user|


Purpose: Tracks P6 license assignments.

---
3. External/Custom Tables

A01_ZASELPS001 (SAP HR Data)


| Column        | Description |

| Sicil No.     | Employee ID |

| Adı Soyadı    | Full name   |

| Kullanıcı Adı | Username    |

| Masraf Yeri   | Cost center |

| Unvan         | Job title   |

| Aktivite Türü | Activity type|


Purpose: Contains HR data from SAP (ZASELPS001 report). Used to include employees not in P6 (e.g., Production, Logistics staff).

-- Query example (line 338-351)
SELECT [Adı Soyadı], [Kullanıcı Adı], [Masraf Yeri], [Sicil No.], Unvan
FROM [DatabaseName].[dbo].[A01_ZASELPS001]
WHERE ([Masraf Yeri] = '1234567-8'
    AND [Sicil No.] IN ('1','2',...))


HR02_rehisRehber (REHIS Contact Directory)


| Column | Description   |

| sicil  | Employee ID   |

| eposta | Email address |

| ad     | Full name     |


Purpose: Contains employee contact information. Used to get email addresses for notifications.

-- Query example (lines 367-370)
SELECT sicil, eposta, ad
FROM [DatabaseName].[HRO2_rehisRehber]


4. Derived Authorization Tables (R Data Files)

These are created from the source tables and saved to .Rdata files:

user_base (in yetkilendirme.Rdata)

# Created from DC01_user_base + additional manual entries
user_base <- rbind(users,
    c("admin", "admin", "ADMIN", "12345", "SUPERADMIN", -1, "1"),
    c("kalite", "kalite", "ADMIN", "kalite", "KAL", -2, "1234567-2"),
    c("test", "test", "ADMIN", "test", "TEST", -3, "1234567-3"),
    c("uretim", "uretim", "ADMIN", "uretim", "URETIM", -4, "1234567-4")
) %>%
  pivot_longer(cols = c("KullaniciAdi", "SicilNo"), names_to = "Type", values_to = "KullaniciAdi")

Key Feature: The pivot_longer creates two rows per user - one with KullaniciAdi and one with SicilNo. This allows users to log in with either their username or employee ID.

---
proje_KYP_base (Quality Department Authorization)


| Column       | Description                       |

| KullaniciAdi | Username                          |

| SicilNo      | Employee ID                       |

| EPSKodu      | EPS codes accessible (comma-separated)|

| EPSTanimi    | EPS names                         |


Purpose: Maps Quality department staff (KY-P role) to specific EPS nodes. Quality staff can view all projects under their assigned EPS.

-- Query (lines 926-975)
SELECT LOWER(CONVERT(NVARCHAR(20),u.Name)) AS KullaniciAdi,
    CASE
        WHEN uo.OBSObjectId = 6623
            THEN '4_ABCDE,4_ABCDF,4_ABCDG,4_ABCDH,4_ABCDJ'
        WHEN uo.OBSObjectId = 6791
            THEN '4_BCDEF,4_BCDEG,4_BCDEH,4_BCDEJ,4_BCDEG'
        ELSE CONVERT(NVARCHAR(20),e.Id)
    END AS EPSKodu
FROM DC01_userr u
INNER JOIN DC01_userOBS uo ON uo.UserObjectId = u.ObjectId
WHERE ProjectProfileObjectId = 126 -- Rapor Erişim - PY

---
proje_PY_base (Project Manager Authorization)


| Column       | Description                             |

| KullaniciAdi | Username                                |

| SicilNo      | Employee ID                             |

| ProjeKodu    | Project IDs accessible (comma-separated)|


Purpose: Maps Project Managers (PY role) to specific projects. PMs can only view their assigned projects.

-- Query (lines 979-1005)
SELECT LOWER(CONVERT(NVARCHAR(20),uo.UserName)) AS KullaniciAdi,
    STRING_AGG(CONVERT(NVARCHAR(20),p.Id),',') AS ProjeKodu
FROM DC01_userOBS uo
INNER JOIN DC01_project p ON p.OBSObjectId = uo.OBSObjectId
WHERE uo.OBSName LIKE '%PY'
    AND uo.ProjectProfileObjectId IN (51, 81) -- PY and PPTS
GROUP BY uo.UserName

---
proje_DirP_base (Director Authorization)


| Column       | Description                                    |

| KullaniciAdi | Username                                       |

| SicilNo      | Employee ID (manual mapping for some directors)|

| EPSKodu      | EPS codes accessible                           |


Purpose: Maps Directors (DIR-P role) to their directorate's EPS nodes. Directors can view all projects under their directorate.

---
yetkiProje (Project-EPS Lookup)


| Column       | Description   |

| Id           | Project ID    |

| ProjectName  | Project name  |

| ParentEpsId  | Parent EPS ID |

| EPSName      | EPS name      |


Purpose: Lookup table that maps projects to their parent EPS. Used by authorization functions to filter projects.

-- Query (lines 1071-1076)
SELECT p.Id, p.Name AS ProjectName, p.ParentEpsId, e.Name AS EPSName
FROM DC01_project p
LEFT JOIN DC01_EPS e ON e.ObjectId = p.ParentEPSObjectId
WHERE CONVERT(VARCHAR, e.ID) IN ('4_ABCDF','4_ABCDG',...)
    AND CONVERT(VARCHAR, p.Status) IN ('Active','Planned')

---
personelBilgileri (Employee Information)


| Column           | Description        |

| SicilNo          | Employee ID        |

| KaynakAdi        | Full name          |

| KullaniciAdi     | Username           |

| MasrafYeriKodu   | Cost center code   |

| MasrafYeri       | Cost center name   |

| EPosta           | Email              |

| Telefon          | Phone              |

| Unvan            | Job title          |

| AnaRolKodu       | Primary role code  |

| AnaRolTanimi     | Primary role name  |

| KaynakYoneticisi | Manager name       |

| AktifKaynak      | Active status      |

| ObjectId         | P6 Resource ObjectId|

| UserObjectId     | P6 User ObjectId   |


Purpose: Comprehensive employee information used throughout the application for displaying user details and filtering by various criteria.

---
5. Table Relationship Diagram

    +----------------------------------------------------------------------------------------------+
    |                                    TABLE RELATIONSHIPS                                       |
    |                                                                                              |
    |  +------------------+       +------------------------+       +-------------------------+    |
    |  | DC01_userr       |       | DC01_resource          |       | DC01_userOBS            |    |
    |  |                  |       |                        |       |                         |    |
    |  | ObjectId (PK)    |<------| UserObjectId           |       | UserObjectId            |----+
    |  | Name             |       | ObjectId (PK)          |       | OBSObjectId             |    |
    |  +------------------+       | EmployeeId             |       | ProjectProfileObjectId  |    |
    |                             | Name                   |       +-------------------------+    |
    |                             | Title                  |                    |                 |
    |                             +------------------------+                    ▼                 |
    |                                         |                     +------------------+          |
    |                                         |                     | DC01_OBS         |          |
    |                                         |                     |                  |          |
    |                                         |                     | ObjectId (PK)    |          |
    |                                         |                     | OBSName          |          |
    |                                         |                     +------------------+          |
    |                                         ▼                                                   |
    |                             +------------------------+                                      |
    |                             | DC01_resourceCode      |       +------------------+           |
    |                             | Assignment             |       | DC01_EPS         |           |
    |                             |                        |       |                  |           |
    |                             | ResourceObjectId       |       | ObjectId (PK)    |           |
    |                             | ResourceCodeObjectId   |       | Id               |           |
    |                             | ResourceCodeValue      |       | Name             |           |
    |                             +------------------------+       | OBSObjectId      |           |
    |                                         |                    +------------------+           |
    |  +------------------+                   ▼                             |                     |
    |  | DC01_resourceCode|                                                 ▼                     |
    |  |                  |                                                                       |
    |  | ObjectId (PK)    |                   +------------------------------------------+       |
    |  | CodeValue        |                   |              DC01_project                 |       |
    |  | Description      |                   |                                           |       |
    |  | CodeTypeObjectId |                   | ObjectId (PK)                             |       |
    |  +------------------+                   | Id                                        |       |
    |                                         | Name                                      |       |
    |                                         | Status                                    |       |
    |                                         | OBSObjectId                               |       |
    |                                         | ParentEPSObjectId                         |       |
    |                                         +------------------------------------------+       |
    |                                                                                              |
    |                                                                                              |
    |                  +------------------------------------------------------------------+       |
    |                  |                DC01_user_base (Result)                           |       |
    |                  |                                                                  |       |
    |                  | KullaniciAdi  <-- DC01_userr.Name                                |       |
    |                  | KaynakAdi     <-- DC01_resource.Name                             |       |
    |                  | MasrafYeriKodu<-- DC01_resourceCodeAssignment.CodeValue          |       |
    |                  | Yetki         <-- DC01_userOBS (computed)                        |       |
    |                  | UserObjectId  <-- DC01_userr.ObjectId                            |       |
    |                  +------------------------------------------------------------------+       |
    +----------------------------------------------------------------------------------------------+

---
6. Authorization Logic Summary

| Role       | Source Table                              | Access Pattern                   |

| SUPERADMIN | Hardcoded usernames                       | Full access to everything        |

| ADMIN      | DC01_userOBS (ProfileId=87,126) + OBS=595 | Full access + Admin Panel        |

| DIR        | DC01_resourceAccess + DC01_userOBS        | All projects in cost centers     |

| DIR-P      | proje_DirP_base                           | All prjs und. assign. EPS cod    |

| KY-P       | proje_KYP_base                            | All prjs und. assign. EPS codes  |

| KY         | DC01_userOBS                              | View access to all projects      |

| PY         | proje_PY_base                             | Only assign. prjs (Proj ID)      |

| KAL        | Manual entry                              | Limit. access for Qual dept      |

| TEST       | Manual entry                              | Limited access for Test dept     |

| UR         | A01_ZASELPS001                            | Production department access     |


---
7. Data Refresh Cycle

All tables are refreshed daily via dailyQueryScript.R:

# Execution sequence:
1. Query DC01_resource → personelBilgileri
2. Query DC01_userr + DC01_userOBS + DC01_OBS + DC01_EPS → user_base temp
3. Query A01_ZASELPS001 → merge with user_base
4. Save user_base to yetkilendirme.Rdata
5. Query proje_KYP_base → save
6. Query proje_PY_base → save
7. Query proje_DirP_base → save
8. Query yetkiProje → save

The application loads these .Rdata files at startup:
load(file = "Rdata/yetkilendirme.Rdata", envir = .GlobalEnv)  # user_base, proje_*_base, yetkiProje
load(file = "Rdata/personelBilgileri.Rdata", envir = .GlobalEnv)
