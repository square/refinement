# Refinement Changes

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
