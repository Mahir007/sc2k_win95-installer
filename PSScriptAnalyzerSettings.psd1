@{
    ExcludeRules = @(
        # Interactive installer: output is for the user, not the pipeline
        'PSAvoidUsingWriteHost'
        # Internal helpers, not cmdlets
        'PSUseShouldProcessForStateChangingFunctions'
        'PSUseSingularNouns'
    )
}
