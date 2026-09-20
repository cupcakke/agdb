def sum_array [n] (arr: [n]i64) : i64 =
  reduce (+) 0i64 arr

def map_add [n] (arr: [n]i64) (value: i64) : [n]i64 =
  map (\x -> x + value) arr

def map_multiply [n] (arr: [n]i64) (factor: i64) : [n]i64 =
  map (\x -> x * factor) arr

def filter_positive [n] (arr: [n]i64) : []i64 =
  filter (\x -> x > 0i64) arr

def dot_product [n] (a: [n]i64) (b: [n]i64) : i64 =
  reduce (+) 0i64 (map2 (*) a b)

def vector_add [n] (a: [n]i64) (b: [n]i64) : [n]i64 =
  map2 (+) a b

def vector_sub [n] (a: [n]i64) (b: [n]i64) : [n]i64 =
  map2 (-) a b

def vector_scale [n] (arr: [n]i64) (scalar: i64) : [n]i64 =
  map (\x -> x * scalar) arr

def find_max [n] (arr: [n]i64) : i64 =
  reduce i64.max i64.lowest arr

def find_min [n] (arr: [n]i64) : i64 =
  reduce i64.min i64.highest arr

def count_positive [n] (arr: [n]i64) : i64 =
  reduce (+) 0i64 (map (\x -> if x > 0i64 then 1i64 else 0i64) arr)

def sum_matrix [n] [m] (mat: [n][m]i64) : i64 =
  reduce (+) 0i64 (map (\row -> reduce (+) 0i64 row) mat)

def map_matrix [n] [m] (mat: [n][m]i64) (value: i64) : [n][m]i64 =
  map (\row -> map (\x -> x + value) row) mat

def matrix_transpose [n] [m] (mat: [n][m]i64) : [m][n]i64 =
  transpose mat

def matrix_multiply [m] [n] [p] (a: [m][n]i64) (b: [n][p]i64) : [m][p]i64 =
  let transposed_b = transpose b
  in map (\row ->
            map (\column -> reduce (+) 0i64 (map2 (*) row column))
                transposed_b)
         a

def prefix_sum [n] (arr: [n]i64) : [n]i64 =
  scan (+) 0i64 arr

def scatter_array [n] [k] (dest: [n]i64) (indices: [k]i64) (values: [k]i64) : [n]i64 =
  scatter (copy dest) indices values

def gather [n] [k] (src: [n]i64) (indices: [k]i64) : [k]i64 =
  map (\i -> src[i]) indices

def partition_array [n] (arr: [n]i64) (pivot: i64) : ([]i64, []i64) =
  let left = filter (\x -> x <= pivot) arr
  let right = filter (\x -> x > pivot) arr
  in (left, right)

def histogram [n] (arr: [n]i64) (num_bins: i64) : []i64 =
  let bins = if num_bins <= 0i64 || n == 0i64 then 0i64 else num_bins
  in if bins == 0i64
     then replicate bins 0i64
     else let min_val = find_min arr
          let max_val = find_max arr
          let value_range = u64.i64 max_val - u64.i64 min_val
          in if value_range == 0u64
             then let result = replicate bins 0i64
                  in result with [0i64] = n
             else let bin_count = u64.i64 bins
                  let quotient = value_range / bin_count
                  let remainder = value_range % bin_count
                  let bin_size = quotient + (if remainder == 0u64 then 0u64 else 1u64)
                  in loop counts = replicate bins 0i64
                     for x in arr do
                       let offset = u64.i64 x - u64.i64 min_val
                       let raw_bin = offset / bin_size
                       let bin = if raw_bin >= bin_count
                                 then bins - 1i64
                                 else i64.u64 raw_bin
                       let old_count = counts[bin]
                       in counts with [bin] = old_count + 1i64

def flatten_matrix [n] [m] (mat: [n][m]i64) : []i64 =
  flatten mat

def flatten_3d [n] [m] [p] (arr: [n][m][p]i64) : []i64 =
  flatten (flatten arr)

def zip_arrays [n] (a: [n]i64) (b: [n]i64) : [n](i64, i64) =
  zip a b

def unzip_array [n] (arr: [n](i64, i64)) : ([n]i64, [n]i64) =
  unzip arr

def all_equal [n] (arr: [n]i64) : bool =
  if n == 0i64
  then true
  else let first = arr[0i64]
       in reduce (&&) true (map (\x -> x == first) arr)

def any_positive [n] (arr: [n]i64) : bool =
  reduce (||) false (map (\x -> x > 0i64) arr)

def all_positive [n] (arr: [n]i64) : bool =
  reduce (&&) true (map (\x -> x > 0i64) arr)

def replicate_array (n: i64) (value: i64) : []i64 =
  let count = if n <= 0i64 then 0i64 else n
  in replicate count value

def iota_array (n: i64) : []i64 =
  let count = if n <= 0i64 then 0i64 else n
  in iota count

def update_array [n] (arr: [n]i64) (index: i64) (value: i64) : [n]i64 =
  let result = copy arr
  in result with [index] = value

def update_matrix [n] [m] (mat: [n][m]i64) (row: i64) (col: i64) (value: i64) : [n][m]i64 =
  let row_copy = copy mat[row]
  let updated_row = row_copy with [col] = value
  let result = copy mat
  in result with [row] = updated_row

def mean_array [n] (arr: [n]f64) : f64 =
  if n == 0i64
  then 0.0f64
  else reduce (+) 0.0f64 arr / f64.i64 n

def variance_array [n] (arr: [n]f64) : f64 =
  if n == 0i64
  then 0.0f64
  else let mean = mean_array arr
       let squared_deviations =
         map (\x ->
                let deviation = x - mean
                in deviation * deviation)
             arr
       in reduce (+) 0.0f64 squared_deviations / f64.i64 n

def std_dev_array [n] (arr: [n]f64) : f64 =
  f64.sqrt (variance_array arr)

def normalize_array [n] (arr: [n]f64) : [n]f64 =
  let mean = mean_array arr
  let std = std_dev_array arr
  in if std == 0.0f64
     then map (\_ -> 0.0f64) arr
     else map (\x -> (x - mean) / std) arr

def min_max_normalize [n] (arr: [n]f64) : [n]f64 =
  if n == 0i64
  then arr
  else let min_val = reduce f64.min f64.highest arr
       let max_val = reduce f64.max f64.lowest arr
       let value_range = max_val - min_val
       in if value_range == 0.0f64
          then map (\_ -> 0.0f64) arr
          else map (\x -> (x - min_val) / value_range) arr

def euclidean_distance [n] (a: [n]f64) (b: [n]f64) : f64 =
  f64.sqrt (reduce (+) 0.0f64 (map (\x -> x * x) (map2 (-) a b)))

def cosine_similarity [n] (a: [n]f64) (b: [n]f64) : f64 =
  let dot = reduce (+) 0.0f64 (map2 (*) a b)
  let magnitude_a = f64.sqrt (reduce (+) 0.0f64 (map (\x -> x * x) a))
  let magnitude_b = f64.sqrt (reduce (+) 0.0f64 (map (\x -> x * x) b))
  let denominator = magnitude_a * magnitude_b
  in if denominator == 0.0f64
     then 0.0f64
     else dot / denominator

def softmax [n] (arr: [n]f64) : [n]f64 =
  if n == 0i64
  then arr
  else let max_val = reduce f64.max f64.lowest arr
       let exp_values = map (\x -> f64.exp (x - max_val)) arr
       let exp_sum = reduce (+) 0.0f64 exp_values
       in if exp_sum == 0.0f64
          then map (\_ -> 0.0f64) exp_values
          else map (\x -> x / exp_sum) exp_values

def relu [n] (arr: [n]f64) : [n]f64 =
  map (\x -> if x > 0.0f64 then x else 0.0f64) arr

def sigmoid [n] (arr: [n]f64) : [n]f64 =
  map (\x ->
         if x >= 0.0f64
         then 1.0f64 / (1.0f64 + f64.exp (0.0f64 - x))
         else let exponent = f64.exp x
              in exponent / (1.0f64 + exponent))
      arr

def tanh_array [n] (arr: [n]f64) : [n]f64 =
  map f64.tanh arr

def leaky_relu [n] (arr: [n]f64) (alpha: f64) : [n]f64 =
  map (\x -> if x > 0.0f64 then x else alpha * x) arr

def elu [n] (arr: [n]f64) (alpha: f64) : [n]f64 =
  map (\x -> if x > 0.0f64 then x else alpha * (f64.exp x - 1.0f64)) arr

def convolve_1d [n] [k] (signal: [n]f64) (kernel: [k]f64) : []f64 =
  let count = if k <= 0i64 || k > n then 0i64 else n - k + 1i64
  in tabulate count
              (\i ->
                 reduce (+) 0.0f64
                        (map (\j -> signal[i + j] * kernel[k - 1i64 - j])
                             (iota k)))

def moving_average [n] (arr: [n]f64) (window: i64) : []f64 =
  let count = if window <= 0i64 || window > n then 0i64 else n - window + 1i64
  in tabulate count
              (\i ->
                 reduce (+) 0.0f64 (map (\j -> arr[i + j]) (iota window))
                 / f64.i64 window)

def exponential_moving_average [n] (arr: [n]f64) (alpha: f64) : [n]f64 =
  let decay = 1.0f64 - alpha
  let terms =
    map2 (\i x -> if i == 0i64 then (0.0f64, x) else (decay, alpha * x))
         (iota n)
         arr
  let combined =
    scan (\((weight_a, value_a): (f64, f64)) ((weight_b, value_b): (f64, f64)) ->
            (weight_a * weight_b, weight_b * value_a + value_b))
         (1.0f64, 0.0f64)
         terms
  in map (\(_, value) -> value) combined

def find_peaks [n] (arr: [n]f64) (threshold: f64) : []i64 =
  let candidate_count = if n < 3i64 then 0i64 else n - 2i64
  let candidates = tabulate candidate_count (\i -> i + 1i64)
  in filter (\i ->
               arr[i] > arr[i - 1i64] && arr[i] > arr[i + 1i64]
               && arr[i] > threshold)
            candidates

entry main : i64 =
  0i64
