param (
    [Parameter(Mandatory=$false)]
    [string] $pat,
    [Parameter(Mandatory=$false)]
    [string] $buildsourceversion
)

function ExecutarSql {
    param (
        [string] $Query
    )

    $clientid = $env:clientid
    $tenantid = $env:tenantid
    $secret = $env:secret

    $requestBody = @{
        resource     = "https://database.windows.net/"
        grant_type   = "client_credentials"
        client_id    = $clientid
        client_secret= $secret
    }

    $accessTokenResponse = Invoke-RestMethod -Method POST `
        -Uri "https://login.microsoftonline.com/$tenantid/oauth2/token" `
        -Body $requestBody `
        -ContentType "application/x-www-form-urlencoded"

    $access_token = $accessTokenResponse.access_token

    # Execute the SQL query
    Invoke-Sqlcmd -ServerInstance "<<SERVIDOR DO SYNAPSE>" `
        -Database "<<DATABASE>>" `
        -AccessToken $access_token `
        -query $Query
}

$folderPath = "/sqlscript"
$tablePrefixRegex = "^$folderPath/(scpt_)"
#pr_|scpt_ag_|scpt_dm_|scpt_tmp_|scpt_cg_|scpt_ct_
$viewPrefixRegex = "$folderPath/scpt_v_"

$organization = "<<ORGANIZATIONDEVOPS>>"
$project = "<<PROJETO>>"
$repoId = "<<PRJETO>>"
$baseUrl = "https://dev.azure.com/$organization/$project/_apis/git/repositories/$repoId"

$base64Auth = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(":$pat"))
$authorizationHeader = @{ Authorization = "Basic $base64Auth" }
$commitUrl = "$baseUrl/commits/$buildsourceversion/changes?api-version=6.1-preview.1"

try {
    $response = Invoke-RestMethod -Uri $commitUrl -Headers $authorizationHeader -Method Get -ErrorAction Stop

    foreach ($change in $response.changes) {
        $filePath = $change.item.path

        if ($change.item.gitObjectType -eq "blob" -and $filePath -like "$folderPath*") {
            $fileUrl = "$baseUrl/items?path=$filePath&versionDescriptor.versionType=commit&versionDescriptor.version=$buildsourceversion&recursionLevel=None&api-version=7.0"
            
            try {
                $fileResponse = Invoke-RestMethod -Uri $fileUrl -Headers $authorizationHeader -Method Get -ErrorAction Stop

                if ($fileResponse) {
                    $fileName = $fileResponse.name
                    Write-Host "File name: $fileName"

                    $query = $fileResponse.properties.content.query
                    Write-Host "Query: $query"

                    # Check if the file corresponds to a table or view based on its prefix
                    $isTable = $filePath -match $tablePrefixRegex
                    $isView = $filePath -match $viewPrefixRegex

                    if ($isTable) {
                        # Execute the SQL query for tables
                        ExecutarSql -Query $query
                    } elseif ($isView) {
                        # Execute the SQL query for views
                        ExecutarSql -Query $query
                    } else {
                        Write-Host "File does not match any expected prefix."
                    }
                }
            } catch {
                Write-Host "Error retrieving file: $_"
            }
        }
    }
} catch {
    Write-Host "Error retrieving commit information: $_"
}