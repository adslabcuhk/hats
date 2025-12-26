import sys
import numpy as np
from scipy import stats

def calculate_confidence_interval(data):
    
    mean = np.mean(data)
    
    confidence_level = 0.95
    degrees_of_freedom = len(data) - 1
    t_critical = stats.t.ppf((1 + confidence_level) / 2, degrees_of_freedom)
    margin_of_error = t_critical * np.std(data, ddof=1) / np.sqrt(len(data))
    
    lower_bound = mean - margin_of_error
    upper_bound = mean + margin_of_error
    
    return mean, lower_bound, upper_bound

if __name__ == "__main__":
    data = [float(x) for x in sys.argv[1:]]
    
    mean, lower_bound, upper_bound = calculate_confidence_interval(data)

    print("Mean:", mean)
    print("95% Confidence Interval: [{:.2f}, {:.2f}]".format(lower_bound, upper_bound))



# Example usage:
# python script.py 4 7 8 9 10 12 13 14 14 15
