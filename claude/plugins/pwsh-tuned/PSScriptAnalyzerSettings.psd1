# PSScriptAnalyzer settings for pwsh-tuned@local: only the Error-severity rules run. Warnings and information would be
# sent to Claude after every edit and cost tokens. Parse errors come from the PowerShell parser, not from these rules.
# PowerShellEditorServices passes its own -Severity (Error, Warning, Information), which overrides a Severity key here,
# so the rules are listed by name: (Get-ScriptAnalyzerRule -Severity Error).RuleName in PSScriptAnalyzer 1.24.0.
@{
    IncludeRules = @(
        'PSAvoidUsingComputerNameHardcoded'
        'PSAvoidUsingConvertToSecureStringWithPlainText'
        'PSAvoidUsingUsernameAndPasswordParams'
        'PSReservedParams'
        'PSUseCompatibleSyntax'
        'PSDSCStandardDSCFunctionsInResource'
        'PSDSCUseIdenticalMandatoryParametersForDSC'
        'PSDSCUseIdenticalParametersForDSC'
    )
}
