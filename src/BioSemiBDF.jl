module BioSemiBDF

  using StatsBase, DSP

  export read_bdf, merge_bdf, write_bdf, crop_bdf, downsample_bdf

  mutable struct BioSemiRawData
    header::Dict
    data::Matrix
    labels::Array
    time::Array
    triggers::Dict
    status::Array
  end

  """
  function read_bdf(filename::AbstractString; header_only::Bool = false, channels = Array{Any}[])

  Reads BioSemi Data Format (bdf) files.
  See https://www.biosemi.com/faq_file_format.htm for file format details.
  ### Inputs:
  * filename
  ### Outputs:
  * BioSemiRawData struct with the following fields
  * header Dict
  * data (channels * samples) Matrix
  * time
  * triggers Dict
  * status Array
  ### Examples:
  ```julia
  dat1 = read_bdf("filename1.bdf")
  write_bdf(dat3)
  ```
  """
  function read_bdf(filename::AbstractString; header_only::Bool = false, channels = Array{Any}[])

    fid = open(filename, "r")

    # header fields
    id1 = read!(fid, Array{UInt8}(undef, 1))
    id2 = ascii(String(read!(fid, Array{UInt8}(undef, 7))))
    text1 = ascii(String(read!(fid, Array{UInt8}(undef, 80))))
    text2 = ascii(String(read!(fid, Array{UInt8}(undef, 80))))
    start_date = ascii(String(read!(fid, Array{UInt8}(undef, 8))))
    start_time = ascii(String(read!(fid, Array{UInt8}(undef, 8))))
    num_bytes_header = parse(Int, strip(ascii(String(read!(fid, Array{UInt8}(undef, 8))))))
    data_format = strip(ascii(String(read!(fid, Array{UInt8}(undef, 44)))))
    num_data_records = parse(Int, strip(ascii(String(read!(fid, Array{UInt8}(undef, 8))))))
    duration_data_records = parse(Int, ascii(String(read!(fid, Array{UInt8}(undef, 8)))))
    num_channels = parse(Int, ascii(String(read!(fid, Array{UInt8}(undef, 4)))))

    channel_labels = Array{String}(undef, num_channels)
    transducer_type = Array{String}(undef, num_channels)
    channel_unit = Array{String}(undef, num_channels)
    physical_min = Array{Int32}(undef, num_channels)
    physical_max = Array{Int32}(undef, num_channels)
    digital_min = Array{Int32}(undef, num_channels)
    digital_max = Array{Int32}(undef, num_channels)
    pre_filter = Array{String}(undef, num_channels)
    num_samples = Array{Int}(undef, num_channels)
    reserved = Array{String}(undef, num_channels)
    scale_factor = Array{Float32}(undef, num_channels)
    sample_rate = Array{Int}(undef, num_channels)

    # read header information
    for i = 1:num_channels
      channel_labels[i] = strip(ascii(String(read!(fid, Array{UInt8}(undef, 16)))))
    end
    for i = 1:num_channels
      transducer_type[i] = strip(ascii(String(read!(fid, Array{UInt8}(undef, 80)))))
    end
    for i = 1:num_channels
      channel_unit[i] = strip(ascii(String(read!(fid, Array{UInt8}(undef, 8)))))
    end
    for i = 1:num_channels
      physical_min[i] = parse(Int, strip(ascii(String(read!(fid, Array{UInt8}(undef, 8))))))
    end
    for i = 1:num_channels
      physical_max[i] = parse(Int, strip(ascii(String(read!(fid, Array{UInt8}(undef, 8))))))
    end
    for i = 1:num_channels
      digital_min[i] = parse(Int, strip(ascii(String(read!(fid, Array{UInt8}(undef, 8))))))
    end
    for i = 1:num_channels
      digital_max[i] = parse(Int, strip(ascii(String(read!(fid, Array{UInt8}(undef, 8))))))
    end
    for i = 1:num_channels
      pre_filter[i] = strip(ascii(String(read!(fid, Array{UInt8}(undef, 80)))))
    end
    for i = 1:num_channels
      num_samples[i] = parse(Int, ascii(String(read!(fid, Array{UInt8}(undef, 8)))))
    end
    for i = 1:num_channels
      reserved[i] = strip(ascii(String(read!(fid, Array{UInt8}(undef, 32)))))
    end
    for i = 1:num_channels
      scale_factor[i] = Float32(physical_max[i]-physical_min[i])/ (digital_max[i]-digital_min[i])
      sample_rate[i] = num_samples[i]/duration_data_records
    end

    # create header dictionary
    header = Dict{String, Any}(
    "filename" => filename,
    "id1" => id1,
    "id2" => id2,
    "text1" => text1,
    "text2" => text2,
    "start_date" => start_date,
    "start_time" => start_time,
    "num_bytes_header" => num_bytes_header,
    "data_format" => data_format,
    "num_data_records" => num_data_records,
    "duration_data_records" => duration_data_records,
    "num_channels" => num_channels,
    "channel_labels" => channel_labels,
    "transducer_type" => transducer_type,
    "channel_unit" => channel_unit,
    "physical_min" => physical_min,
    "physical_max" => physical_max,
    "digital_min" => digital_min,
    "digital_max" => digital_max,
    "pre_filter" => pre_filter,
    "num_samples" => num_samples,
    "reserved" => reserved,
    "scale_factor" => scale_factor,
    "sample_rate" => sample_rate
    )
    if header_only
      return header
    end

    # read data
    bdf = read!(fid, Array{UInt8}(undef, 3*(num_data_records*num_channels*num_samples[1])))
    close(fid)

    if !isempty(channels)  # specific channel labels/numbers given
      channels = channel_idx(header["channel_labels"], channels)
    else
      channels = 1:num_channels
    end
    labels = header["channel_labels"][channels[1:end-1]]

    # last channel is trigger channel
    dat_chans = Matrix{Float32}(undef, length(channels)-1, (num_data_records*num_samples[1]))
    trig_chan = Array{Int16}(undef, num_data_records*num_samples[1])
    status_chan = Array{Int16}(undef, num_data_records*num_samples[1])
    pos = 1;
    for rec = 0:(num_data_records-1)
      idx = 1
      for chan = 1:num_channels
        if chan in channels  # selected channel
          if chan < num_channels
            for samp = 1:num_samples[1]
              dat_chans[idx, rec*num_samples[1]+samp] = Float32(((Int32(bdf[pos]) << 8) | (Int32(bdf[pos+1]) << 16) | (Int32(bdf[pos+2]) << 24)) >> 8) * scale_factor[chan]
              pos += 3
            end
          else  # last channel is always Status channel
            for samp = 1:num_samples[1]
              trig_chan[rec*num_samples[1]+samp] = ((Int16(bdf[pos])) | (Int16(bdf[pos+1]) << 8))
              status_chan[rec*num_samples[1]+samp] = Int16(bdf[pos+2])
              pos += 3
            end
          end
          idx += 1
        else # channel not selected
          pos += num_samples[1]*3
        end
      end
    end

    # time
    time = collect(0:size(dat_chans, 2) - 1) / sample_rate[1]

    # events
    trig_idx = findall(diff(trig_chan) .>= 1) .+ 1
    trig_val = trig_chan[trig_idx]

    # create triggers dictionary
    triggers = Dict{String, Any}(
    "raw" => trig_chan,
    "idx" => trig_idx,
    "val" => trig_val,
    "count" => sort(countmap(trig_val)),
    "time" => hcat(trig_val, pushfirst!(diff(trig_idx), 0) / header["sample_rate"][1])
    )

    return BioSemiRawData(header, dat_chans, labels, time, triggers, status_chan)

  end

  """
  function write_bdf(bdf_in::BioSemiRawData)

  Write BioSemiRaw structs to *.bdf file.
  See https://www.biosemi.com/faq_file_format.htm for file format details.

  ### Inputs:
  * BioSemiRawData struct

  ### Examples:
  ```julia
  dat1 = read_bdf("filename1.bdf")
  write_bdf(dat1)
  """
  function write_bdf(bdf_in::BioSemiRawData)

    fid = open(bdf_in.header["filename"], "w")

    # id1 1 byte
    write(fid, 0xff)
    # id2 7 bytes
    for i in bdf_in.header["id2"]
      write(fid, UInt8(i))
    end
    # text1 80 bytes
    for i in bdf_in.header["text1"]
      write(fid, UInt8(i))
    end
    # text2 80 bytes
    for i in bdf_in.header["text2"]
      write(fid, UInt8(i))
    end
    # start_date 8 bytes
    for i in bdf_in.header["start_date"]
      write(fid, UInt8(i))
    end
    # start_time 8 bytes
    for i in bdf_in.header["start_time"]
      write(fid, UInt8(i))
    end
    # num_bytes_header 8 bytes
    for i in rpad(string(bdf_in.header["num_bytes_header"]), 8)
      write(fid, UInt8(i))
    end
    # data_format 44 bytes
    for i in rpad(bdf_in.header["data_format"], 44)
      write(fid, UInt8(i))
    end
    # num_data_records 8 bytes
    for i in rpad(string(bdf_in.header["num_data_records"]), 8)
      write(fid, UInt8(i))
    end
    # duration_data_records 8 bytes
    for i in rpad(string(bdf_in.header["duration_data_records"]), 8)
      write(fid, UInt8(i))
    end
    # num_channels 4 bytes
    for i in rpad(string(bdf_in.header["num_channels"]), 4)
      write(fid, UInt8(i))
    end
    # channel_labels 16 bytes
    for i in bdf_in.header["channel_labels"]
      for j in rpad(i, 16)
        write(fid, UInt8(j))
      end
    end
    # transducer_type 80 bytes
    for i in bdf_in.header["transducer_type"], j in rpad(i, 80)
      write(fid, UInt8(j))
    end
    # channel unit 8 bytes
    for i in bdf_in.header["channel_unit"], j in rpad(i, 8)
      write(fid, UInt8(j))
    end
    # physical min 8 bytes
    for i in bdf_in.header["physical_min"], j in rpad(i, 8)
      write(fid, UInt8(j))
    end
    # physical max 8 bytes
    for i in bdf_in.header["physical_max"], j in rpad(i, 8)
      write(fid, UInt8(j))
    end
    # digital min 8 bytes
    for i in bdf_in.header["digital_min"], j in rpad(i, 8)
      write(fid, UInt8(j))
    end
    # digital max 8 bytes
    for i in bdf_in.header["digital_max"], j in rpad(i, 8)
      write(fid, UInt8(j))
    end
    # pre filter 80 bytes
    for i in bdf_in.header["pre_filter"], j in rpad(i, 80)
      write(fid, UInt8(j))
    end
    # num_samples
    for i in bdf_in.header["num_samples"], j in rpad(i, 8)
      write(fid, UInt8(j))
    end
    # reserved 32 bytes
    for i in bdf_in.header["reserved"], j in rpad(i, 32)
      write(fid, UInt8(j))
    end

    # write data
    data = round.(Int32, (bdf_in.data ./ bdf_in.header["scale_factor"][1:end-1]))
    trigs = bdf_in.triggers["raw"]
    status = bdf_in.status

    num_data_records = bdf_in.header["num_data_records"]::Int64
    num_samples = bdf_in.header["num_samples"][1]::Int64
    num_channels = bdf_in.header["num_channels"]::Int64

    bdf = Array{UInt8}(undef, 3*(num_data_records*num_channels*num_samples))

    pos = 1
    for rec = 0:(num_data_records-1)
      for chan = 1:num_channels
        if chan < num_channels
          for samp = 1:num_samples
            data_val = data[chan, rec*num_samples + samp]::Int32
            bdf[pos  ] = (data_val % UInt8)
            bdf[pos+1] = ((data_val >> 8) % UInt8)
            bdf[pos+2] = ((data_val >> 16) % UInt8)
            pos += 3
          end
        else  # last channel is Status channel
          for samp = 1:num_samples
            trig_val = trigs[rec*num_samples + samp]::Int16
            status_val = status[rec*num_samples + samp]::Int16
            bdf[pos  ] = trig_val % UInt8
            bdf[pos+1] = (trig_val >> 8) % UInt8
            bdf[pos+2] = (status_val) % UInt8
            pos += 3
          end
        end
      end
    end

    write(fid, Array{UInt8}(bdf))
    close(fid)

  end

  """
  Merge BioSemiRaw structs to single BioSemiRaw struct. Checks that the
    input BioSemiRaw structs have the same number of channels, same channel
    labels and that each channel has the same sample rate.

  ### Examples:
  ```julia
  dat1 = read_bdf("filename1.bdf")
  dat2 = read_bdf("filename2.bdf")
  dat3 = merge_bdf([dat1, dat2], "filename3.bdf")
  write_bdf(dat3)
  ```
  """
  function merge_bdf(bdf_in::Array{BioSemiRawData}, filename_out::AbstractString)

    # check data structs to merge have same number of channels
    num_chans = (x -> x.header["num_channels"]).(bdf_in)
    if !all(x -> x == num_chans[1], num_chans)
     error("Different number of channels in bdf_in")
    end

    # check data structs to merge have same channel labels
    chan_labels = (x -> x.header["channel_labels"]).(bdf_in)
    if !all(y -> y == chan_labels[1], chan_labels)
     error("Different channel labels bdf_in")
    end

    # check data structs to merge have same sample rate
    sample_rate = (x -> x.header["sample_rate"]).(bdf_in)
    if !all(y -> y == sample_rate[1], sample_rate)
     error("Different sample rate in bdf_in")
    end

    # make copy so that bdf_in is not altered
    bdf_out = deepcopy(bdf_in[1])
    bdf_out.header["filename"] = filename_out
    bdf_out.header["num_data_records"] = sum((x -> x.header["num_data_records"]).(bdf_in))

    # merged dat_chan Matrix (channels x samples)
    bdf_out.data = hcat((x -> x.data).(bdf_in)...)

    # merged time ans status array
    bdf_out.time = collect(0:size(bdf_out.data, 2) -1) / bdf_in[1].header["sample_rate"][1]
    bdf_out.status = vcat((x -> x.status).(bdf_in)...)

    # merged triggers dict with offset idx
    for bdf in bdf_in[2:end]
     idx_offset = size(bdf.data, 2)
     bdf_out.triggers["idx"] = vcat(bdf_out.triggers["idx"], bdf.triggers["idx"] .+ idx_offset)
    end
    bdf_out.triggers["raw"] = vcat((x -> x.triggers["raw"]).(bdf_in)...)
    bdf_out.triggers["val"] = vcat((x -> x.triggers["val"]).(bdf_in)...)
    bdf_out.triggers["count"] = sort(countmap(bdf_out.triggers["val"]))

    return bdf_out

  end

   """
   function crop_bdf(bdf_in::BioSemiRawData, crop_type::AbstractString, val::Array{Int}, filename_out::AbstractString)

   Recuce the length of the recorded data. The borded upon which to crop the bdf file can be defined using either
   a start and end trigger ("triggers") or a start and end record ("records").

   ### Examples:
   ```julia
   dat1 = read_bdf("filename1.bdf")
   dat2 = crop_bdf(dat1, "triggers", [1 2])  # between first trigger 1 and last trigger 2
   dat3 = crop_bdf(dat1, "records", [1 100]) # data records 1 to 100 inclusive
   ```
   """
   function crop_bdf(bdf_in::BioSemiRawData, crop_type::AbstractString, val::Array{Int}, filename_out::AbstractString)

     if length(val) != 2
       error("val should be of length 2")
     end

     sample_rate = bdf_in.header["sample_rate"][1]
     if crop_type == "triggers"

       # find trigger value index
       trigStart = findfirst(x -> x == val[1], bdf_in.triggers["val"])
       trigEnd = findlast(x -> x == val[2], bdf_in.triggers["val"])
       idxStart = bdf_in.triggers["idx"][trigStart]
       idxEnd = bdf_in.triggers["idx"][trigEnd]

       # need to find boundardy equal to record breaks
       borders = collect(1:sample_rate:size(bdf_in.data)[2])
       idxStart =  findlast(x -> x  <= idxStart, borders) * sample_rate
       idxEnd   = (findfirst(x -> x >= idxEnd,   borders) * sample_rate) - 1

     elseif crop_type == "records"

       idxStart = ((val[1]-1) * sample_rate) + 1
       idxEnd   =  (val[2]    * sample_rate)

       # find trigger value index
       trigStart = findfirst(x -> x >= idxStart, bdf_in.triggers["idx"])
       trigEnd   = findlast(x ->  x <= idxEnd,   bdf_in.triggers["idx"])

     else
       error("crop_type not recognized!")
     end

     # copy data and crop
     bdf_out = deepcopy(bdf_in)
     bdf_out.header["filename"] = filename_out
     bdf_out.header["num_data_records"] = (idxEnd - idxStart) * sample_rate
     bdf_out.data = bdf_out.data[:, idxStart:idxEnd]
     bdf_out.time = collect(0:size(bdf_out.data, 2) -1) / bdf_in[1].header["sample_rate"][1]

     # update triggers
     bdf_out.triggers["idx"] = bdf_out.triggers["idx"][trigStart:trigEnd]
     bdf_out.triggers["val"] = bdf_out.triggers["val"][trigStart:trigEnd]
     bdf_out.triggers["count"] = sort(countmap(bdf_out.triggers["val"]))

     return bdf_out

   end

   """
   function downsample_bdf(bdf_in::BioSemiRawData, dec_factor::Int64)
   Reduce the sampling rate within a BioSemiRawData struct by an integer factor (dec_factor).

   ### Examples:
   ```julia
   dat1 = read_bdf("filename1.bdf")
   dat2 = downsample_bdf(dat1, 2)
   ```
   """
   # TO DO: mirror data/subtract channel mean to avoid edge artifacts
   function downsample_bdf(bdf_in::BioSemiRawData, dec_factor::Int64)

     bdf_out = deepcopy(bdf_in)

     data = Matrix{Float32}(undef, size(bdf_out.data)[1], convert(Int64, (size(bdf_out.data)[2])/dec_factor))
     for i in 1:size(bdf_out.data, 1)
       data[i, :] = convert(Array{Float32}, transpose(resample(bdf_out.data[i,:], 1/dec_factor)))
     end
     bdf_out.data = data

     bdf_out.header["sample_rate"] = convert(Array{Int64}, (bdf_out.header["sample_rate"] ./ dec_factor))
     bdf_out.time = collect(0:size(bdf_out.data, 2) -1) / bdf_out.header["sample_rate"][1]

     return bdf_out

   end

   """
   function channel_idx(labels_in::Array{String}, channels::Array{Int})

   Return channel index given labels and desired channel labels.
   """

   function channel_idx(labels_in::Array{String}, channels::Array{String})
     channels = [findfirst(x -> x == y, labels_in) for y in channels]
     if any(x -> x == nothing, channels)
       error("A requested channel label is not in the bdf file!")
     else
       println("Selecting channels:", labels_in[channels])
     end
     return unique(append!(channels, (length(labels_in) + 1)))
   end

   """
   function channel_idx(labels_in::Array{String}, channels::Array{Int})
   Return channel index given labels and desired channel index.
   """
   function channel_idx(labels_in::Array{String}, channels::Array{Int})
     if any(x -> x > length(labels_in), channels) || any(x -> x < 0, channels)
       error("A requested channel number is not in the bdf file!")
     else
       println("Selecting channels:", labels_in[channels])
     end
     return unique(append!(channels, (length(labels_in) + 1)))
   end

end
