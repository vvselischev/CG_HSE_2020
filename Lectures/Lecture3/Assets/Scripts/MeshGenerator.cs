using System;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;

[RequireComponent(typeof(MeshFilter))]
public class MeshGenerator : MonoBehaviour
{
    public MetaBallField Field = new MetaBallField();

    private const int CubesCount = 40;
    private const float Eps = 0.01f;
    
    private MeshFilter _filter;
    private Mesh _mesh;
    
    private List<Vector3> vertices = new List<Vector3>();
    private List<Vector3> normals = new List<Vector3>();
    private List<int> indices = new List<int>();

    /// <summary>
    /// Executed by Unity upon object initialization. <see cref="https://docs.unity3d.com/Manual/ExecutionOrder.html"/>
    /// </summary>
    private void Awake()
    {
        // Getting a component, responsible for storing the mesh
        _filter = GetComponent<MeshFilter>();
        
        // instantiating the mesh
        _mesh = _filter.mesh = new Mesh();
        
        // Just a little optimization, telling unity that the mesh is going to be updated frequently
        _mesh.MarkDynamic();
    }

    /// <summary>
    /// Executed by Unity on every frame <see cref="https://docs.unity3d.com/Manual/ExecutionOrder.html"/>
    /// You can use it to animate something in runtime.
    /// </summary>
    private void Update()
    {
        var minX = Field.Balls.Min(t => t.position.x) - Field.BallRadius;
        var maxX = Field.Balls.Max(t => t.position.x) + Field.BallRadius;
        var minY = Field.Balls.Min(t => t.position.y) - Field.BallRadius;
        var maxY = Field.Balls.Max(t => t.position.y) + Field.BallRadius;
        var minZ = Field.Balls.Min(t => t.position.z) - Field.BallRadius;
        var maxZ = Field.Balls.Max(t => t.position.z) + Field.BallRadius;

        var min = Math.Min(minX, Math.Min(minY, minZ)) - 1;
        var max = Math.Max(maxX, Math.Max(maxY, maxZ)) + 1;

        var size = (max - min) / CubesCount;
        
        var cubes = new List<Vector3[]>();

        for (var i = min; i < max; i += size)
        {
            for (var j = min; j < max; j += size)
            {
                for (var k = min; k < max; k += size)
                {
                    cubes.Add(CreateCube(i, j, k, size));
                }
            }
        }

        vertices.Clear();
        indices.Clear();
        normals.Clear();
        
        Field.Update();

        foreach (var cube in cubes)
        {
            var mask = 0;
            for (var i = 0; i < cube.Length; i++)
            {
                if (Field.F(cube[i]) > 0)
                {
                    mask |= 1 << i;
                }
            }

            var caseToTrianglesCount = MarchingCubes.Tables.CaseToTrianglesCount[mask];
            var caseToVertices = MarchingCubes.Tables.CaseToVertices[mask];

            for (var i = 0; i < caseToTrianglesCount; i++)
            {
                var edges = new[]
                {
                    caseToVertices[i].x,
                    caseToVertices[i].y,
                    caseToVertices[i].z
                };
                
                for (var j = 0; j < 3; j++)
                {
                    var edgeEndpoints = MarchingCubes.Tables._cubeEdges[edges[j]];
                    var first = cube[edgeEndpoints[0]];
                    var second = cube[edgeEndpoints[1]];
                    
                    indices.Add(vertices.Count);
                    var intersectionFraction = Field.F(second) / (Field.F(second) - Field.F(first));
                    var vertex = intersectionFraction * first + (1 - intersectionFraction) * second;
                    vertices.Add(vertex);

                    var normal = new Vector3(
                        Field.F(vertex + Eps * Vector3.right) - Field.F(vertex + Eps * Vector3.left),
                        Field.F(vertex + Eps * Vector3.up) - Field.F(vertex + Eps * Vector3.down),
                        Field.F(vertex + Eps * Vector3.forward) - Field.F(vertex + Eps * Vector3.back)
                    );
                    normals.Add(-normal.normalized);
                }
            }
        }

        // Here unity automatically assumes that vertices are points and hence (x, y, z) will be represented as (x, y, z, 1) in homogenous coordinates
        _mesh.Clear();
        _mesh.SetVertices(vertices);
        _mesh.SetTriangles(indices, 0);
        _mesh.SetNormals(normals);

        // Upload mesh data to the GPU
        _mesh.UploadMeshData(false);
    }

    private Vector3[] CreateCube(float x, float y, float z, float size)
    {
        return new[]
        {
            new Vector3(x, y, z), // 0
            new Vector3(x, y + size, z), // 1
            new Vector3(x + size, y + size, z), // 2
            new Vector3(x + size, y, z), // 3
            new Vector3(x, y, z + size), // 4
            new Vector3(x, y + size, z + size), // 5
            new Vector3(x + size, y + size, z + size), // 6
            new Vector3(x + size, y, z + size), // 7
        };
    }
}