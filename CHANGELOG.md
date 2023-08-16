# Refinement Changes

## 0.7.0 (2023-08-11)

##### Breaking Changes

Since the introduction of the class '**Refinement**' 
[in Ruby 3.1](https://ruby-doc.org/core-3.1.0/Refinement.html), there is a naming 
collision that requires this gem to be updated. 

We have prefixed the `Refinement` module with `Sq::` to minimize the amount of 
downstream changes required, in addition to maintaining the meaning and purpose 
of the project.

##### Enhancements

* Update dependencies to modern versions

## 0.3.1 (2019-08-09)

##### Bug Fixes

* Take into consideration product reference names when refinining.


## 0.3.0 (2019-08-09)

##### Bug Fixes

* Multiple YAML used keys paths for the same file will no longer cause the YAML
  to be parsed multiple times.  


## 0.2.2 (2019-04-08)

No changes.  


## 0.2.1 (2019-04-08)

##### Bug Fixes

* Record augmenting paths for pods that are not linked against any user targets.  


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
