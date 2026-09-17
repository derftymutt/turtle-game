class_name FormatUtil

## Formats an integer with comma thousands separators, e.g. 12345 -> "12,345".
static func comma_int(n: int) -> String:
	var digits := str(abs(n))
	var grouped := ""
	for i in range(digits.length()):
		if i > 0 and (digits.length() - i) % 3 == 0:
			grouped += ","
		grouped += digits[i]
	return ("-" if n < 0 else "") + grouped
