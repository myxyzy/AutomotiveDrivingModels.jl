using AutomotiveDrivingModels

using RandomForestBehaviors
using DynamicBayesianNetworkBehaviors

##############################
# PARAMETERS
##############################

const INCLUDE_FILE_BASE = "realworld"
const N_SIMULATIONS_PER_TRACE = 10
const DEFAULT_TRACE_HISTORY = 2*DEFAULT_FRAME_PER_SEC
const N_BAGGING_SAMPLES = 10
const CONFIDENCE_LEVEL = 0.95

const MAX_CV_OPT_TIME_PER_MODEL = 60.0 # [s]
const AM_ON_TULA = gethostname() == "tula"
const INCLUDE_FILE = Pkg.dir("AutomotiveDrivingModels", "scripts", "extract_params.jl")
const INCLUDE_NAME = splitdir(splitext(INCLUDE_FILE)[1])[2]

include(INCLUDE_FILE)

################################
# METRICS
################################

metric_types_test_frames = [LoglikelihoodMetric]
metric_types_test_frames_bagged = [LoglikelihoodMetric]
metric_types_train_frames = [LoglikelihoodMetric]
metric_types_train_frames_bagged = [LoglikelihoodMetric]

metric_types_test_traces = [
                            EmergentKLDivMetric{symbol(SPEED)},
                            EmergentKLDivMetric{symbol(D_CL)},
                            # EmergentKLDivMetric{symbol(TIMEGAP_X_FRONT)},
                            RootWeightedSquareError{symbol(SPEED), 0.5},
                            RootWeightedSquareError{symbol(SPEED), 1.0},
                            RootWeightedSquareError{symbol(SPEED), 1.5},
                            RootWeightedSquareError{symbol(SPEED), 2.0},
                            RootWeightedSquareError{symbol(SPEED), 2.5},
                            RootWeightedSquareError{symbol(SPEED), 3.0},
                            RootWeightedSquareError{symbol(SPEED), 3.5},
                            RootWeightedSquareError{symbol(SPEED), 4.0},
                            RootWeightedSquareError{symbol(D_CL), 0.5},
                            RootWeightedSquareError{symbol(D_CL), 1.0},
                            RootWeightedSquareError{symbol(D_CL), 1.5},
                            RootWeightedSquareError{symbol(D_CL), 2.0},
                            RootWeightedSquareError{symbol(D_CL), 2.5},
                            RootWeightedSquareError{symbol(D_CL), 3.0},
                            RootWeightedSquareError{symbol(D_CL), 3.5},
                            RootWeightedSquareError{symbol(D_CL), 4.0},
                            # RootWeightedSquareError{symbol(TIMEGAP_X_FRONT), 0.5},
                            # RootWeightedSquareError{symbol(TIMEGAP_X_FRONT), 1.0},
                            # RootWeightedSquareError{symbol(TIMEGAP_X_FRONT), 1.5},
                            # RootWeightedSquareError{symbol(TIMEGAP_X_FRONT), 2.0},
                            # RootWeightedSquareError{symbol(TIMEGAP_X_FRONT), 2.5},
                            # RootWeightedSquareError{symbol(TIMEGAP_X_FRONT), 3.0},
                            # RootWeightedSquareError{symbol(TIMEGAP_X_FRONT), 3.5},
                            # RootWeightedSquareError{symbol(TIMEGAP_X_FRONT), 4.0},
                           ]
metric_types_test_traces_bagged = [
                                   EmergentKLDivMetric{symbol(SPEED)},
                                   EmergentKLDivMetric{symbol(D_CL)},
                                   # EmergentKLDivMetric{symbol(TIMEGAP_X_FRONT)},
                                   # RootWeightedSquareError{symbol(SPEED), 0.5},
                                   # RootWeightedSquareError{symbol(SPEED), 1.0},
                                   # RootWeightedSquareError{symbol(SPEED), 1.5},
                                   # RootWeightedSquareError{symbol(SPEED), 2.0},
                                   # RootWeightedSquareError{symbol(SPEED), 2.5},
                                   # RootWeightedSquareError{symbol(SPEED), 3.0},
                                   # RootWeightedSquareError{symbol(SPEED), 3.5},
                                   # RootWeightedSquareError{symbol(SPEED), 4.0},
                                   # RootWeightedSquareError{symbol(D_CL), 0.5},
                                   # RootWeightedSquareError{symbol(D_CL), 1.0},
                                   # RootWeightedSquareError{symbol(D_CL), 1.5},
                                   # RootWeightedSquareError{symbol(D_CL), 2.0},
                                   # RootWeightedSquareError{symbol(D_CL), 2.5},
                                   # RootWeightedSquareError{symbol(D_CL), 3.0},
                                   # RootWeightedSquareError{symbol(D_CL), 3.5},
                                   # RootWeightedSquareError{symbol(D_CL), 4.0},
                                   # RootWeightedSquareError{symbol(TIMEGAP_X_FRONT), 0.5},
                                   # RootWeightedSquareError{symbol(TIMEGAP_X_FRONT), 1.0},
                                   # RootWeightedSquareError{symbol(TIMEGAP_X_FRONT), 1.5},
                                   # RootWeightedSquareError{symbol(TIMEGAP_X_FRONT), 2.0},
                                   # RootWeightedSquareError{symbol(TIMEGAP_X_FRONT), 2.5},
                                   # RootWeightedSquareError{symbol(TIMEGAP_X_FRONT), 3.0},
                                   # RootWeightedSquareError{symbol(TIMEGAP_X_FRONT), 3.5},
                                   # RootWeightedSquareError{symbol(TIMEGAP_X_FRONT), 4.0},
                                  ]

################################
# LOAD TRAIN AND VALIDATION SETS
################################

include(Pkg.dir("AutomotiveDrivingModels", "scripts", "model_params.jl"))
nmodels = length(behaviorset)

################################
# MAIN LOOP
################################

for dset_filepath_modifier in (
    "_freeflow",
    # "_following",
    # "_lanechange",
    )

    println(dset_filepath_modifier)

    METRICS_OUTPUT_FILE = joinpath(EVALUATION_DIR, "validation_results" * dset_filepath_modifier * ".jld")
    MODEL_OUTPUT_JLD_FILE = joinpath(EVALUATION_DIR, "validation_models" * dset_filepath_modifier * ".jld")
    TRAIN_VALIDATION_JLD_FILE = joinpath(EVALUATION_DIR, "train_validation_split" * dset_filepath_modifier * ".jld")
    DATASET_JLD_FILE = joinpath(EVALUATION_DIR, "dataset2" * dset_filepath_modifier * ".jld")

    dset = JLD.load(DATASET_JLD_FILE, "model_training_data")::ModelTrainingData2

    preallocated_data_dict = Dict{AbstractString, AbstractVehicleBehaviorPreallocatedData}()
    for (behavior_name, train_def) in behaviorset
        preallocated_data_dict[behavior_name] = preallocate_learning_data(dset, train_def.trainparams)
    end

    hyperparam_counts = Dict{AbstractString, Array(Matrix{Int}}()
    for (behavior_name, train_def) in behaviorset
        max_range = maximum([λ->length(λ), train_def.hyperparams])
        hyperparam_counts[behavior_name] = zeros(length(train_def.hyperparams, max_range))
    end

    print("loading sim resources "); tic()
    runlogs_original = load_runlogs(dset)
    streetnets = load_streetnets(runlogs_original)
    toc()

    cv_split_outer = get_fold_assignment_across_drives(dset)

    nframes = nrow(dset.dataframe)
    ntraces = length(cv_split_outer.seg_assignment)
    frame_logls = Array(Float64, nframes, ntraces, nmodels) # logl for each frame under each run (we can back out TRAIN and TEST)

    foldinds = collect(1:ntraces)
    bagged_selection = collect(1:ntraces)
    model_names = collect(keys(behaviorset))

    # make pdset copies that are only as large as needed
    # (contain history and horizon from runlogs_original)
    println("preallocating memory for traces"); tic()

    arr_runlogs_for_simulation = Array(Matrix{RunLog}, nmodels)
    frame_starts_sim = Array(Int, ntraces) # new frame_start for the truncated arr_runlogs_for_simulation
    for k in 1 : nmodels
        arr_runlogs_for_simulation[k] = Array(RunLog, ntraces, N_SIMULATIONS_PER_TRACE)
    end
    for (i,ind) in enumerate(foldinds)

        seg = dset.runlog_segments[ind]
        frame_start = max(1, seg.frame_start - DEFAULT_TRACE_HISTORY)
        runlog_sim = deepcopy(runlogs_original[seg.runlog_id], frame_start, seg.frame_end)
        frame_starts_sim[i] = clamp(seg.frame_start-DEFAULT_TRACE_HISTORY, 1, DEFAULT_TRACE_HISTORY+1)

        for k in 1 : nmodels
            for j in 1 : N_SIMULATIONS_PER_TRACE
                arr_runlogs_for_simulation[k][i,j] = deepcopy(runlog_sim)
            end
        end
    end
    toc()

    ######################################
    # TRAIN A MODEL FOR EACH FOLD USING CV
    ######################################

    for fold in 1 : cv_split_outer.nfolds
        #=
        1 - find optimal hyperparam set
        2 - update trace metrics for given traces
        3 - update mean frame likelihood
        =#

        println("fold ", fold, " / ", cv_split_outer.nfolds)

        # create an inner split where we remove the current fold
        cv_split_inner = deepcopy(cv_split_outer)
        for (i,v) in enumerate(cv_split_inner.frame_assignment)
            if v == fold
                cv_split_inner.frame_assignment[i] = 0
            elseif v > fold
                cv_split_inner.frame_assignment[i] -= 1
            end
        end
        cv_split_inner.nfolds -= 1
        @assert(cv_split_inner.nfolds > 0)

        ##############

        print("\toptimizing hyperparameters\n"); tic()
        for (behavior_name, train_def) in behaviorset
            println(behavior_name)
            preallocated_data = preallocated_data_dict[behavior_name]
            AutomotiveDrivingModels.optimize_hyperparams_cyclic_coordinate_ascent!(
                    train_def, dset, preallocated_data, cv_split_inner)
        end
        toc()

        # update the count
        for (behavior_name, train_def) in behaviorset
            hyperparam_count = hyperparam_counts[behavior_name]
            for (i, λ) in enumerate(train_def.hyperparams)
                hyperparam_count[i, λ.index_of_default] += 1
            end
        end

        print("\ttraining models  "); tic()
        models = train(behaviorset, dset, preallocated_data_dict, fold, cv_split_outer)
        toc()

        print("\tcomputing likelihoods  "); tic()
        for (i,behavior_name) in enumerate(model_names)
            behavior = models[behavior_name]
            for frameind in 1 : nframes
                if trains_with_nona(behavior)
                    frame_logls[frameind, fold, i] = calc_action_loglikelihood(behavior, dset.dataframe_nona, frameind)
                else
                    frame_logls[frameind, fold, i] = calc_action_loglikelihood(behavior, dset.dataframe, frameind)
                end
            end
        end
        toc()

        println("\tsimulating"); tic()
        for (k,behavior_name) in enumerate(model_names)
            behavior = models[behavior_name]

            print("\t\t", behavior_name, "  "); tic()
            for i in 1 : ntraces
                if cv_split_outer.seg_assignment[i] == fold # in test
                    # simulate
                    seg = dset.runlog_segments[i]
                    frame_start = frame_starts_sim[i]
                    frame_end = frame_start + seg.frame_end - seg.frame_start

                    for l in 1 : N_SIMULATIONS_PER_TRACE
                        runlog = arr_runlogs_for_simulation[k][i, l]
                        sn = streetnets[runlog.header.map_name]
                        simulate!(runlog, sn, behavior, seg.carid, frame_start, frame_end)
                    end
                end
            end
            toc()
        end
        toc()
    end

    #########################################################

    print("Hyperparam Statistics: ")
    for (behavior_name, train_def) in behaviorset

        counts = hyperparam_counts[behavior_name]

        println(behavior_name)
        for (j,λ) in enumerate(train_def.hyperparams)
            most_freqent_index = indmax(counts[j,:])
            @printf("\t%-15s %s", string(λ.sym)*":", string(λ.range[most_freqent_index]))
        end

        print("i  ")
        for λ in train_def.hyperparams
            @printf("%15s", string(λ.sym))
        end
        print("\n")

        for i in 1 : size(counts, 2)
            @printf("%2d ", i)
            for (j,λ) in enumerate(train_def.hyperparams)
                @printf("%15d", counts[j,i])
            end
        end
        println("\n\n")
    end


    #########################################################

    print("Exctracting frame stats  "); tic()

    metrics_sets_test_frames = Array(Vector{BehaviorFrameMetric}, nmodels)
    metrics_sets_train_frames = Array(Vector{BehaviorFrameMetric}, nmodels)
    metrics_sets_test_frames_bagged = Array(Vector{BaggedMetricResult}, nmodels)
    metrics_sets_train_frames_bagged = Array(Vector{BaggedMetricResult}, nmodels)
    metrics_sets_test_traces = Array(Vector{BehaviorTraceMetric}, nmodels)
    metrics_sets_test_traces_bagged = Array(Vector{BaggedMetricResult}, nmodels)

    for k in 1:nmodels
        print("\tmodel: ", k, "  "); tic()

        arr_logl_test = Float64[]
        arr_logl_train = Float64[]

        for j in 1 : cv_split_outer.nfolds
            for i in 1 : nframes
                if cv_split_outer.frame_assignment[i] == j
                    push!(arr_logl_test, frame_logls[i,j,k])
                elseif cv_split_outer.frame_assignment[i] != 0
                    push!(arr_logl_train, frame_logls[i,j,k])
                end
            end
        end

        metrics_sets_test_frames[k] = BehaviorFrameMetric[LoglikelihoodMetric(mean(arr_logl_test))]
        metrics_sets_train_frames[k] = BehaviorFrameMetric[LoglikelihoodMetric(mean(arr_logl_train))]
        metrics_sets_test_frames_bagged[k] = BaggedMetricResult[BaggedMetricResult(LoglikelihoodMetric, arr_logl_test, N_BAGGING_SAMPLES)]
        metrics_sets_train_frames_bagged[k] = BaggedMetricResult[BaggedMetricResult(LoglikelihoodMetric, arr_logl_train, N_BAGGING_SAMPLES)]

        # TRACES

        retval_straight = Array(BehaviorTraceMetric, length(metric_types_test_traces))
        retval_bagged = Array(BaggedMetricResult, length(metric_types_test_traces_bagged))
        for (i,M) in enumerate(metric_types_test_traces)
            retval_straight[i] = extract(M, dset.runlog_segments,
                                         runlogs_original, arr_runlogs_for_simulation[k], frame_starts_sim,
                                         streetnets, foldinds, bagged_selection)
            if i ≤ length(retval_bagged)
                retval_bagged[i] = BaggedMetricResult(M, dset.runlog_segments,
                                             runlogs_original, arr_runlogs_for_simulation[k], frame_starts_sim,
                                             streetnets, foldinds, bagged_selection,
                                             N_BAGGING_SAMPLES, CONFIDENCE_LEVEL)
            end
        end

        metrics_sets_test_traces[k] = retval_straight
        metrics_sets_test_traces_bagged[k] = retval_bagged

        toc()
    end
    toc()

    println("\tLOGL TEST")
    for i in 1 : length(metrics_sets_test_frames)
        logl_μ = get_score(metrics_sets_test_frames[i][1])
        logl_b = metrics_sets_test_frames_bagged[i][1].confidence_bound
        @printf("\t%-20s logl %6.3f ± %6.3f\n", model_names[i], logl_μ, logl_b)
    end
    println("")

    println("\tLOGL TRAIN")
    for i in 1 : length(metrics_sets_train_frames)
        logl_μ = get_score(metrics_sets_train_frames[i][1])
        logl_b = metrics_sets_train_frames_bagged[i][1].confidence_bound
        @printf("\t%-20s logl %6.3f ± %6.3f\n", model_names[i], logl_μ, logl_b)
    end
    println("")

    println("metrics_sets_test_traces: ")
    println(metrics_sets_test_traces)
    println("metrics_sets_test_traces_bagged: ")
    println(metrics_sets_test_traces_bagged)

    # JLD.save(METRICS_OUTPUT_FILE,
    #          "model_names",                      model_names,
    #          "metrics_sets_test_frames",         metrics_sets_test_frames,
    #          "metrics_sets_test_frames_bagged",  metrics_sets_test_frames_bagged,
    #          "metrics_sets_train_frames",        metrics_sets_train_frames,
    #          "metrics_sets_train_frames_bagged", metrics_sets_train_frames_bagged,
    #          "metrics_sets_test_traces",         metrics_sets_test_traces,
    #          "metrics_sets_test_traces_bagged",  metrics_sets_test_traces_bagged,
    #         )
end

# println("DONE")
println("DONE")
exit()