using BioSemiBDF
using Test

@testset "Newtest17-256" begin

    bdf_filename = joinpath(dirname(@__FILE__), "Newtest17-256.bdf")
    dat = read_bdf(bdf_filename)

    # some header details
    @test isequal(dat.header["num_bytes_header"], 4608)
    @test isequal(dat.header["num_channels"], 17)
    @test isequal(dat.header["num_data_records"], 60)
    @test isequal(dat.header["sample_rate"][1], 256)

    # some data
    @test isequal(size(dat.data), (16, 15360))

    # channel labels
    @test isequal(dat.header["channel_labels"][1], dat.labels[1])
    @test isequal(dat.header["channel_labels"][16], dat.labels[16])

    # triggers
    @test isequal(dat.triggers["idx"][1], 415)
    @test isequal(dat.triggers["val"][1], 255)
    @test isequal(dat.triggers["count"][1], 40)

end


@testset "Newtest17-2048" begin

    bdf_filename = joinpath(dirname(@__FILE__), "Newtest17-2048.bdf")
    dat = read_bdf(bdf_filename)

    # some header details
    @test isequal(dat.header["num_bytes_header"], 4608)
    @test isequal(dat.header["num_channels"], 17)
    @test isequal(dat.header["num_data_records"], 60)
    @test isequal(dat.header["sample_rate"][1], 2048)

    # some data
    @test isequal(size(dat.data), (16, 122880))

    # channel labels
    @test isequal(dat.header["channel_labels"][1], dat.labels[1])
    @test isequal(dat.header["channel_labels"][16], dat.labels[16])

    # triggers
    @test isequal(dat.triggers["idx"][1], 3353)
    @test isequal(dat.triggers["val"][1], 255)
    @test isequal(dat.triggers["count"][1], 39)

end
