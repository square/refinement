# Refinement Changes

## 0.2.0 (2019-03-21)

##### Enhancements

* Allow filtering schemes for either `:building` or `:testing`,
  since tests can expand their arguments and environment variables based upon
  a build target, and removing the build target could thus break macro expansion
  without any benefit when `xcodebuild build-for-testing / test` is being run,
  since when building for testing or testing, having build entries is not harmful.  


## 0.1.3 (2019-03-20)

##### Bug Fixes

* Fix CLI invocation for repository parsing.  

## 0.1.2 (2019-03-15)

##### Bug Fixes

* Fix reading in current contents for a changed file in a changeset generated from a
  git diff.  

## 0.1.1 (2019-03-06)

##### Bug Fixes

* Use the merge base with the target revision to determine to prior contents of a file.
  This will allow YAML keypath dependencies to resolve correctly, versus reading from the
  current tip of the target branch.  

## 0.1.0 (2019-02-19)

##### Enhancements

* Initial implementation.  
