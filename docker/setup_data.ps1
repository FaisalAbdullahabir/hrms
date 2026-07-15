$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$r = Invoke-WebRequest -Uri "http://localhost:8000/api/method/login" -Method POST -Body "usr=Administrator&pwd=admin" -WebSession $session -UseBasicParsing
Write-Host "Logged in: $($r.StatusCode)"

function Create-Doc($doctype, $data) {
    $json = $data | ConvertTo-Json -Depth 10
    try {
        $res = Invoke-WebRequest -Uri "http://localhost:8000/api/resource/$doctype" -Method POST -Body $json -ContentType "application/json" -WebSession $session -UseBasicParsing
        $obj = $res.Content | ConvertFrom-Json
        Write-Host "  Created: $($obj.data.name)"
        return $true
    } catch {
        $msg = $_.ErrorDetails.Message
        if ($msg -match "already exists") {
            Write-Host "  Exists: $doctype"
            return $false
        }
        Write-Host "  ERROR creating $doctype : $msg"
        return $false
    }
}

Write-Host "`n=== DEPARTMENTS ==="
$departments = @("Engineering", "Human Resources", "Marketing", "Finance", "Operations", "Product", "Design", "Sales", "Legal", "Customer Support")
foreach ($d in $departments) {
    Create-Doc "Department" @{ department_name = $d; company = "Am Technologies Inc" }
}

Write-Host "`n=== DESIGNATIONS ==="
$designations = @("Director", "Vice President", "Manager", "Senior Engineer", "Engineer", "Junior Engineer", "Lead", "Analyst", "Senior Analyst", "Intern", "Executive", "Coordinator", "Specialist", "Senior Manager")
foreach ($d in $designations) {
    Create-Doc "Designation" @{ designation_name = $d }
}

Write-Host "`n=== EMPLOYEE GRADES ==="
@("Grade A - Executive", "Grade B - Manager", "Grade C - Senior", "Grade D - Junior", "Grade E - Intern") | ForEach-Object {
    Create-Doc "Employee Grade" @{ grade_name = $_; company = "Am Technologies Inc" }
}

Write-Host "`n=== EMPLOYMENT TYPES ==="
@("Full Time", "Part Time", "Intern", "Contract", "Consultant") | ForEach-Object {
    Create-Doc "Employment Type" @{ employment_type = $_ }
}

Write-Host "`n=== LEAVE TYPES ==="
$leaveTypes = @(
    @{ leave_type_name = "Annual Leave"; max_continuous_days_allowed = 20; allow_encashment = 1 },
    @{ leave_type_name = "Sick Leave"; max_continuous_days_allowed = 12 },
    @{ leave_type_name = "Personal Leave"; max_continuous_days_allowed = 5 },
    @{ leave_type_name = "Maternity Leave"; max_continuous_days_allowed = 90 },
    @{ leave_type_name = "Paternity Leave"; max_continuous_days_allowed = 10 },
    @{ leave_type_name = "Unpaid Leave"; max_continuous_days_allowed = 0 },
    @{ leave_type_name = "Compensatory Off"; max_continuous_days_allowed = 5 },
    @{ leave_type_name = "Work From Home"; max_continuous_days_allowed = 0 }
)
foreach ($lt in $leaveTypes) {
    Create-Doc "Leave Type" $lt
}

Write-Host "`n=== SHIFT TYPES ==="
$shifts = @(
    @{ name = "Morning Shift"; shift_type = "Morning Shift"; start_time = "08:00:00"; end_time = "17:00:00"; enable_auto_attendance = 1; working_hours_threshold_for_full_day = 8; working_hours_threshold_for_half_day = 4 },
    @{ name = "Afternoon Shift"; shift_type = "Afternoon Shift"; start_time = "13:00:00"; end_time = "22:00:00"; enable_auto_attendance = 1; working_hours_threshold_for_full_day = 8; working_hours_threshold_for_half_day = 4 },
    @{ name = "Night Shift"; shift_type = "Night Shift"; start_time = "21:00:00"; end_time = "06:00:00"; enable_auto_attendance = 1; working_hours_threshold_for_full_day = 8; working_hours_threshold_for_half_day = 4 },
    @{ name = "General Shift"; shift_type = "General Shift"; start_time = "09:00:00"; end_time = "18:00:00"; enable_auto_attendance = 1; working_hours_threshold_for_full_day = 8; working_hours_threshold_for_half_day = 4 }
)
foreach ($s in $shifts) {
    Create-Doc "Shift Type" $s
}

Write-Host "`n=== EMPLOYEES ==="
$employees = @(
    @{ first_name="Sarah"; last_name="Chen"; gender="Female"; date_of_birth="1990-03-15"; date_of_joining="2022-01-10"; department="Engineering"; designation="Manager"; grade="Grade B - Manager"; employment_type="Full Time" },
    @{ first_name="James"; last_name="Wilson"; gender="Male"; date_of_birth="1985-07-22"; date_of_joining="2021-06-01"; department="Engineering"; designation="Lead"; grade="Grade B - Manager"; employment_type="Full Time" },
    @{ first_name="Priya"; last_name="Patel"; gender="Female"; date_of_birth="1992-11-08"; date_of_joining="2022-05-15"; department="Engineering"; designation="Senior Engineer"; grade="Grade C - Senior"; employment_type="Full Time" },
    @{ first_name="Michael"; last_name="Brown"; gender="Male"; date_of_birth="1995-01-30"; date_of_joining="2023-02-01"; department="Engineering"; designation="Engineer"; grade="Grade D - Junior"; employment_type="Full Time" },
    @{ first_name="Emily"; last_name="Davis"; gender="Female"; date_of_birth="1998-06-12"; date_of_joining="2024-01-15"; department="Engineering"; designation="Junior Engineer"; grade="Grade D - Junior"; employment_type="Full Time" },
    @{ first_name="David"; last_name="Martinez"; gender="Male"; date_of_birth="1982-09-05"; date_of_joining="2020-03-01"; department="Human Resources"; designation="Manager"; grade="Grade B - Manager"; employment_type="Full Time" },
    @{ first_name="Lisa"; last_name="Thompson"; gender="Female"; date_of_birth="1991-04-18"; date_of_joining="2022-08-10"; department="Human Resources"; designation="Executive"; grade="Grade C - Senior"; employment_type="Full Time" },
    @{ first_name="Ahmad"; last_name="Khan"; gender="Male"; date_of_birth="1994-12-03"; date_of_joining="2023-06-20"; department="Human Resources"; designation="Coordinator"; grade="Grade D - Junior"; employment_type="Full Time" },
    @{ first_name="Jessica"; last_name="Anderson"; gender="Female"; date_of_birth="1988-02-14"; date_of_joining="2021-01-05"; department="Marketing"; designation="Manager"; grade="Grade B - Manager"; employment_type="Full Time" },
    @{ first_name="Ryan"; last_name="Garcia"; gender="Male"; date_of_birth="1993-08-25"; date_of_joining="2022-09-12"; department="Marketing"; designation="Specialist"; grade="Grade C - Senior"; employment_type="Full Time" },
    @{ first_name="Sophie"; last_name="Lee"; gender="Female"; date_of_birth="1997-05-09"; date_of_joining="2024-03-01"; department="Marketing"; designation="Executive"; grade="Grade D - Junior"; employment_type="Full Time" },
    @{ first_name="Robert"; last_name="Taylor"; gender="Male"; date_of_birth="1980-10-20"; date_of_joining="2019-04-01"; department="Finance"; designation="Director"; grade="Grade A - Executive"; employment_type="Full Time" },
    @{ first_name="Maria"; last_name="Rodriguez"; gender="Female"; date_of_birth="1987-03-07"; date_of_joining="2021-11-15"; department="Finance"; designation="Senior Analyst"; grade="Grade C - Senior"; employment_type="Full Time" },
    @{ first_name="Tom"; last_name="Harris"; gender="Male"; date_of_birth="1996-07-16"; date_of_joining="2023-09-01"; department="Finance"; designation="Analyst"; grade="Grade D - Junior"; employment_type="Full Time" },
    @{ first_name="Anna"; last_name="White"; gender="Female"; date_of_birth="1986-12-11"; date_of_joining="2020-07-01"; department="Operations"; designation="Senior Manager"; grade="Grade B - Manager"; employment_type="Full Time" },
    @{ first_name="Chris"; last_name="Evans"; gender="Male"; date_of_birth="1994-04-28"; date_of_joining="2022-02-14"; department="Operations"; designation="Executive"; grade="Grade C - Senior"; employment_type="Full Time" },
    @{ first_name="Nina"; last_name="Singh"; gender="Female"; date_of_birth="1999-01-22"; date_of_joining="2024-06-01"; department="Operations"; designation="Coordinator"; grade="Grade D - Junior"; employment_type="Full Time" },
    @{ first_name="Alex"; last_name="Kim"; gender="Male"; date_of_birth="1991-06-30"; date_of_joining="2022-04-01"; department="Product"; designation="Manager"; grade="Grade B - Manager"; employment_type="Full Time" },
    @{ first_name="Olivia"; last_name="Wright"; gender="Female"; date_of_birth="1993-11-14"; date_of_joining="2023-01-10"; department="Design"; designation="Lead"; grade="Grade B - Manager"; employment_type="Full Time" },
    @{ first_name="Daniel"; last_name="Clark"; gender="Male"; date_of_birth="1997-08-02"; date_of_joining="2024-02-15"; department="Design"; designation="Engineer"; grade="Grade D - Junior"; employment_type="Full Time" },
    @{ first_name="Rachel"; last_name="Lewis"; gender="Female"; date_of_birth="1989-05-20"; date_of_joining="2021-08-01"; department="Sales"; designation="Manager"; grade="Grade B - Manager"; employment_type="Full Time" },
    @{ first_name="Kevin"; last_name="Walker"; gender="Male"; date_of_birth="1995-09-11"; date_of_joining="2023-04-01"; department="Sales"; designation="Executive"; grade="Grade C - Senior"; employment_type="Full Time" },
    @{ first_name="Laura"; last_name="Hall"; gender="Female"; date_of_birth="1984-01-08"; date_of_joining="2020-01-15"; department="Legal"; designation="Director"; grade="Grade A - Executive"; employment_type="Full Time" },
    @{ first_name="Mark"; last_name="Young"; gender="Male"; date_of_birth="1992-07-19"; date_of_joining="2022-11-01"; department="Customer Support"; designation="Manager"; grade="Grade B - Manager"; employment_type="Full Time" },
    @{ first_name="Tina"; last_name="Scott"; gender="Female"; date_of_birth="1998-03-25"; date_of_joining="2024-04-01"; department="Customer Support"; designation="Executive"; grade="Grade D - Junior"; employment_type="Full Time" },
    @{ first_name="Carlos"; last_name="Rivera"; gender="Male"; date_of_birth="2000-10-05"; date_of_joining="2024-07-01"; department="Engineering"; designation="Intern"; grade="Grade E - Intern"; employment_type="Intern" }
)

foreach ($emp in $employees) {
    $emp.cell_phone = "+1 555-" + [math]::Floor((Get-Random -Maximum 9000) + 1000)
    Create-Doc "Employee" $emp
}

Write-Host "`n=== DONE ==="
