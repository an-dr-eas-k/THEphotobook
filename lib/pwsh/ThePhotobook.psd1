
@{
    FunctionsToExport = '*'
    CmdletsToExport   = '*'
    VariablesToExport = '*'
    AliasesToExport   = '*'
    NestedModules     = @( 
        "ThePhotobook.psm1", 
        "$($PSScriptRoot)/tools/photoUploadCmdlets.psm1")
    ModuleVersion     = '1.0'
    GUID              = '00000000-0000-0000-0000-000000000000'
    Author            = 'Andreas Kirschner'
    Description       = 'Generates LaTeX for the photobook'
    FormatsToProcess  = @()
    # ScriptsToProcess  = @()
}