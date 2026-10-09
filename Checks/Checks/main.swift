import Foundation

print("— window ordering")
orderingChecks()
print("— search")
fuzzyChecks()
print("— switcher session")
sessionChecks()

exit(failures == 0 ? 0 : 1)
