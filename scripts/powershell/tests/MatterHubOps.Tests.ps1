#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }
# Run: Invoke-Pester -Path scripts/powershell/tests
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester shares BeforeAll variables with It blocks.')]
param()

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'MatterHubOps') -Force
}

Describe 'Get-TagComplianceReport' {
    BeforeAll {
        $required = @('service', 'environment')
        $resources = @(
            [pscustomobject]@{ Name = 'good'; ResourceType = 't'; ResourceGroupName = 'rg'; Tags = @{ service = 'matterhub'; environment = 'dev' } }
            [pscustomobject]@{ Name = 'missing-one'; ResourceType = 't'; ResourceGroupName = 'rg'; Tags = @{ service = 'matterhub' } }
            [pscustomobject]@{ Name = 'blank-value'; ResourceType = 't'; ResourceGroupName = 'rg'; Tags = @{ service = ' '; environment = 'dev' } }
            [pscustomobject]@{ Name = 'no-tags'; ResourceType = 't'; ResourceGroupName = 'rg'; Tags = $null }
            [pscustomobject]@{ Name = 'mixed-case'; ResourceType = 't'; ResourceGroupName = 'rg'; Tags = @{ Service = 'x'; ENVIRONMENT = 'y' } }
        )
        $report = Get-TagComplianceReport -Resource $resources -RequiredTag $required
    }

    It 'marks fully tagged resources compliant' {
        ($report | Where-Object Name -EQ 'good').Compliant | Should -BeTrue
    }

    It 'lists exactly the missing tags' {
        ($report | Where-Object Name -EQ 'missing-one').MissingTags | Should -Be 'environment'
        ($report | Where-Object Name -EQ 'no-tags').MissingTags | Should -Be 'service, environment'
    }

    It 'treats whitespace-only values as missing' {
        ($report | Where-Object Name -EQ 'blank-value').Compliant | Should -BeFalse
    }

    It 'matches tag names case-insensitively' {
        ($report | Where-Object Name -EQ 'mixed-case').Compliant | Should -BeTrue
    }

    It 'handles an empty resource list' {
        @(Get-TagComplianceReport -Resource @() -RequiredTag $required).Count | Should -Be 0
    }
}

Describe 'New-StrongPassword' {
    It 'returns a SecureString by default' {
        New-StrongPassword | Should -BeOfType ([securestring])
    }

    It 'has the requested length and every character class' {
        foreach ($i in 1..50) {
            $p = New-StrongPassword -Length 20 -AsPlainText
            $p.Length | Should -Be 20
            $p | Should -MatchExactly '[A-Z]'
            $p | Should -MatchExactly '[a-z]'
            $p | Should -Match '[0-9]'
            $p | Should -Match '[-_.~]'
            $p | Should -Not -Match '[^A-Za-z0-9\-_.~]'
        }
    }

    It 'does not repeat' {
        (1..20 | ForEach-Object { New-StrongPassword -AsPlainText } | Sort-Object -Unique).Count | Should -Be 20
    }

    It 'rejects weak lengths' {
        { New-StrongPassword -Length 8 } | Should -Throw
    }
}

Describe 'Wait-Condition' {
    It 'returns true as soon as the condition holds' {
        $script:calls = 0
        Mock -ModuleName MatterHubOps Start-Sleep {}
        Wait-Condition -TimeoutSeconds 60 -IntervalSeconds 1 -Condition { $script:calls++; $script:calls -ge 3 } | Should -BeTrue
        $script:calls | Should -Be 3
    }

    It 'returns false after the timeout' {
        Wait-Condition -TimeoutSeconds 1 -IntervalSeconds 1 -Condition { $false } | Should -BeFalse
    }
}

Describe 'Get-RestoreDrillReport' {
    BeforeAll {
        $common = @{
            Environment = 'prod'; Mode = 'PointInTime'; SourceServer = 'psql-a'; RestoredServer = 'psql-b'
            StartedAt = [datetime]'2026-11-03T10:00:00Z'; RtoTargetMinutes = 60; RpoTargetMinutes = 15
        }
    }

    It 'passes when RTO, RPO and validation are all met' {
        $r = Get-RestoreDrillReport @common -RestorePoint ([datetime]'2026-11-03T09:50:00Z') `
            -Duration ([timespan]::FromMinutes(25)) -ValidationPassed $true
        $r | Should -Match '# Database restore drill - prod - PASS'
        $r | Should -Match 'RTO\) \| 25 min'
    }

    It 'fails when the restore was too slow' {
        $r = Get-RestoreDrillReport @common -RestorePoint ([datetime]'2026-11-03T09:50:00Z') `
            -Duration ([timespan]::FromMinutes(90)) -ValidationPassed $true
        $r | Should -Match 'FAIL'
    }

    It 'fails when the data-loss window exceeds the RPO' {
        $r = Get-RestoreDrillReport @common -RestorePoint ([datetime]'2026-11-03T08:00:00Z') `
            -Duration ([timespan]::FromMinutes(10)) -ValidationPassed $true
        $r | Should -Match 'FAIL'
    }

    It 'includes notes' {
        $r = Get-RestoreDrillReport @common -RestorePoint ([datetime]'2026-11-03T09:55:00Z') `
            -Duration ([timespan]::FromMinutes(10)) -ValidationPassed $true -Notes 'first note'
        $r | Should -Match '- first note'
    }
}
