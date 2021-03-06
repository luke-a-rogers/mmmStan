
functions {
  #include create_simplex_dimensions.stan
  #include create_p_step.stan
  #include create_obs_count.stan
  #include partial_sum.stan
}

data {
  // Index limits
  int<lower=2> A; // Number of release and recovery areas
  int<lower=1> G; // Number of release groups
  int<lower=2> L; // Maximum number of time steps at liberty
  int<lower=1> T; // Number of release time steps
  int<lower=1> H; // Number of harvest rate time steps
  int<lower=2> S; // Number of study time steps L + (T - 1) or L + 1
  int<lower=1> P; // Number of movement time steps
  int<lower=1> Q; // Number of harvest rate groups
  int<lower=1> W; // Number of tag reporting rate time steps
  // Constants
  int<lower=1> Y; // Number of time steps per year
  // Tag data
  int<lower=0> x[T, A, G, L, A]; // Tag array
  // Reporting rate
  real<lower=0, upper=1> w[W, A]; // Tag reporting rate array
  // Movement index array
  int<lower=0, upper=1> z[A, A]; // Movement index array
  // Input rates
  real<lower=0, upper=1> u; // Initial tag retention rate (proportion)
  real<lower=0> v; // Tag loss rate
  real<lower=0> m; // Natural mortality rate
  // Index vectors
  int<lower=1> h_index[S]; // Harvest rate time step index
  int<lower=1> p_index[S]; // Movement rate time step index
  int<lower=1> q_index[G]; // Harvest rate group index
  int<lower=1> w_index[S]; // Reporting rate time step index
  // Option constants
  int<lower=0, upper=1> rw; // Include random walk on retention rates
  // Prior parameters
  real<lower=0> h_alpha[Q, H, A];
  real<lower=0> h_beta[Q, H, A];
  real<lower=0> phi_alpha[1];
  real<lower=0> phi_beta[1];
  real<lower=0> sigma_alpha[(rw == 1 && P > 1) ? A : 0]; // dim A or 0
  real<lower=0> sigma_beta[(rw == 1 && P > 1) ? A : 0]; // dim A or 0
  // Fudge constants
  real<lower=0> p_fudge;
  real<lower=0> y_fudge;
}

transformed data {
  // Initialize
  int simplex_dimensions[6] = create_simplex_dimensions(P, A, G, z);
  // Transformed indexes
  real v_step = v / Y;
  real m_step = m / Y;
}

parameters {
  // Harvest rate
  real<lower=0, upper=1> h[Q, H, A];
  // Movement simplexes
  simplex[1] s1[simplex_dimensions[1]]; // Not used
  simplex[2] s2[simplex_dimensions[2]];
  simplex[3] s3[simplex_dimensions[3]];
  simplex[4] s4[simplex_dimensions[4]];
  simplex[5] s5[simplex_dimensions[5]];
  simplex[6] s6[simplex_dimensions[6]];
  // Random walk standard deviation
  real<lower=0> sigma[(rw == 1 && P > 1) ? A : 0]; // Conditional dim A or 0
  // Negative binomial dispersion var = mu + mu^2 / phi
  real<lower=0> phi;
}

transformed parameters {
  // Initialize array version of movement simplexes
  real p1[simplex_dimensions[1], 1];
  real p2[simplex_dimensions[2], 2];
  real p3[simplex_dimensions[3], 3];
  real p4[simplex_dimensions[4], 4];
  real p5[simplex_dimensions[5], 5];
  real p6[simplex_dimensions[6], 6];
  // Initialize fishing mortality rates
  real f[Q, H, A];
  real f_step[Q, H, A];
  // Populate array version of movement simplexes
  for (i in 1:simplex_dimensions[1]) {for (j in 1:1) {p1[i, j] = s1[i, j]; } }
  for (i in 1:simplex_dimensions[2]) {for (j in 1:2) {p2[i, j] = s2[i, j]; } }
  for (i in 1:simplex_dimensions[3]) {for (j in 1:3) {p3[i, j] = s3[i, j]; } }
  for (i in 1:simplex_dimensions[4]) {for (j in 1:4) {p4[i, j] = s4[i, j]; } }
  for (i in 1:simplex_dimensions[5]) {for (j in 1:5) {p5[i, j] = s5[i, j]; } }
  for (i in 1:simplex_dimensions[6]) {for (j in 1:6) {p6[i, j] = s6[i, j]; } }
  // Populate fishing mortality rates
  for (cg in 1:Q) {
    for (ct in 1:H) {
      for (ca in 1:A) {
        f[cg, ct, ca] = -log(1 - h[cg, ct, ca]);
        f_step[cg, ct, ca] = f[cg, ct, ca] / Y;
      }
    }
  }
}

model {
  // Initialize values
  real p_step[G, P, A, A]; // [ , , ca, pa] Movement rates
  real s_step[G, S, A]; // Survival rate
  int release_steps[T];
  int grainsize = 1;
  s_step = rep_array(0, G, S, A);

  // Create stepwise movement rates
  p_step = create_p_step(p_fudge, P, A, G, p1, p2, p3, p4, p5, p6, z);

  // Populate release steps
  for (mt in 1:T) {
    release_steps[mt] = mt;
  }

  // Compute survival
  for (mg in 1:G) {
    for (ct in 1:S) {
      for (ca in 1:A) {
        s_step[mg, ct, ca] = exp(
          -f_step[q_index[mg], h_index[ct], ca]
          - m_step
          - v_step);
      }
    }
  }

  // Dispersion prior
  phi ~ gamma(phi_alpha, phi_beta);

  // Harvest rate priors
  for (cg in 1:Q) {
    for (ct in 1:H) {
      for (ca in 1:A) {
        h[cg, ct, ca] ~ beta(h_alpha[cg, ct, ca], h_beta[cg, ct, ca]);
      }
    }
  }

  // Random walk priors
  if (rw == 1 && P > 1) {
    sigma ~ gamma(sigma_alpha, sigma_beta);
  }

  // Random walk on retention rates (self-movement rates)
  if (rw == 1 && P > 1) {
    for (mg in 1:G) {
      for (ct in 2:P) {
        for (ca in 1:A) {
          p_step[mg, ct, ca, ca] ~ normal(
            p_step[mg, ct - 1, ca, ca],
            sigma[ca]);
        }
      }
    }
  }

  // Likelihood statement using reduce_sum()
  target += reduce_sum(
    partial_sum_lupmf,
    release_steps,
    grainsize,
    S,
    A,
    G,
    L,
    u,
    phi,
    y_fudge,
    h_index,
    p_index,
    q_index,
    w_index,
    w,
    f_step,
    s_step,
    p_step,
    x);
}

generated quantities {
  // Initialize
  real p_step[G, P, A, A]; // Stepwise model version [ , , ca, pa]
  matrix[A, A] p_step_matrix[G, P]; // Stepwise intermediary
  matrix[A, A] p_matrix[G, P]; // Annual intermediary
  real p[A, A, P, G]; // Annual user version [pa, ca, , ,]

  // Create stepwise movement rates
  p_step = create_p_step(p_fudge, P, A, G, p1, p2, p3, p4, p5, p6, z);

  // Populate annual movement rate array
  for (mg in 1:G) {
    for (ct in 1:P) {
      // Populate p_matrix
      for (pa in 1:A) {
        for (ca in 1:A) {
          p_step_matrix[mg, ct, pa, ca] = p_step[mg, ct, ca, pa];
        }
      }
      // Populate annual p_matrix
      p_matrix[mg, ct] = matrix_power(p_step_matrix[mg, ct], Y);
      // Populate annual array p
      for (pa in 1:A) {
        for (ca in 1:A) {
          p[pa, ca, ct, mg] = p_matrix[mg, ct, pa, ca];
        }
      }
    }
  }
}
