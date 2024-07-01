param (
    [Parameter(Mandatory = $false)] [string] $ADOFilesPath,
    [Parameter(Mandatory = $false)] [string] $commit,
    [Parameter(Mandatory = $false)] [string] $pat 
)

$AzureDevOpsAuthenicationHeader = @{Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($pat)")) }

$files=@()

$Uri = "https://dev.azure.com/<ORGANIZATION>/<PROJETO>/_apis/git/repositories/prj-synapse/commits/$($commit)/changes?api-version=7.0"
 
$files = Invoke-RestMethod -Uri $Uri -Method get -Headers $AzureDevOpsAuthenicationHeader 

function validaPipeline{
param(
 [parameter(Mandatory = $false)] [string] $armTemplatePath,
 [parameter(Mandatory = $false)] [PSCustomObject[]] $files
)

$pipelinesError = @()

foreach ($change in $files.changes){
    #Verifica se alguma pipeline foi modificado durante o pull request para validar as modificações
    if($change.item.path.StartsWith('/sqlscript/')){
        #Valida se o arquivo modificado existe (cenário de rename faz referência a um arquivo que não existe e quebra o script sem essa verificação)
        if(test-path -path $armTemplatePath$($change.item.path)){
            $templateJson = Get-Content $armTemplatePath$($change.item.path) | ConvertFrom-Json
            
            #Valida o prefixo do script modificado
            if(!$templateJson.name.StartsWith("scpt_")){
                $pipelinesError += "Sqlscript $($templateJson.name) não começa com 'scpt_'"
            }

            # Valida a descrição do script modificado
            if (-not $templateJson.properties.description) {
                $pipelinesError += "Sqlscript $($templateJson.name) não possui descrição"
            }      
        }
    }
}
    return $pipelinesError
}

$pipelinesOutput = @()

#Chamar a funcion para validar as pipelines
$pipelinesOutput = validaPipeline -armTemplatePath $ADOFilesPath -files $files

if ($pipelinesOutput){
    if($pipelinesOutput){
        $pipelinesOutput | ForEach-Object {
            Write-Warning "$_"
        }
    }
    throw "Erro encontrado, validar warnings acima"
}