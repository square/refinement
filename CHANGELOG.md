# Refinement Changes

## Master

##### Bug Fixes

* Use the merge base with the target revision to determine to prior contents of a file.
  This will allow YAML keypath dependencies to resolve correctly, versus reading from the
  current tip of the target branch.  

## 0.1.0 (2019-02-19)

##### Enhancements

* Initial implementation.  
